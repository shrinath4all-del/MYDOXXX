/**
 * Razorpay payments for bookings (doctor, physio, nurse, technician).
 *
 * The patient pays after a provider accepts (status "Confirmed"). The amount
 * always comes from the booking in Firestore, and the key secret stays here.
 * Each payment is split with Razorpay Route (razorpay_route.js): 10% stays
 * with the app, 90% goes to the provider's linked account, held until the
 * visit is completed.
 *   createRazorpayOrder   -> Razorpay order for the booking's price
 *   verifyRazorpayPayment -> checks the checkout signature, marks it paid
 *   razorpayWebhook       -> backup: marks it paid even if the app closed
 *                            before verifyRazorpayPayment ran
 *
 * Secrets (set once):
 *   firebase functions:secrets:set RAZORPAY_KEY_ID
 *   firebase functions:secrets:set RAZORPAY_KEY_SECRET
 *   firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
 */
const crypto = require("crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { providerTransfer, updatePayoutStatusFromWebhook, splitAmount } = require("./razorpay_route");
const wallet = require("./wallet");
const { appointmentPrice } = require("./pricing");
const { applyRecharge } = require("./chat_recharge");

const KEY_ID = defineSecret("RAZORPAY_KEY_ID");
const KEY_SECRET = defineSecret("RAZORPAY_KEY_SECRET");
const WEBHOOK_SECRET = defineSecret("RAZORPAY_WEBHOOK_SECRET");

// Bookings the patient can pay for: accepted, not started yet
const PAYABLE_STATUSES = new Set(["Confirmed"]);

const db = () => admin.firestore();

function serviceLabel(a) {
  if (a.isTherapistRequest || a.roleTarget === "therapist") return "Physiotherapy session";
  if (a.isNurseRequest || a.roleTarget === "nurse") return "Nurse visit";
  if (a.isTechnicianRequest || a.roleTarget === "technician") return "Lab test at home";
  return "Doctor consultation";
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** Marks the booking paid once (idempotent). */
async function markPaid(appointmentId, { orderId, paymentId, amount, via }) {
  const ref = db().collection("appointments").doc(appointmentId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const a = snap.data();
    if (a.razorpayOrderId !== orderId) return false;
    if (a.paymentStatus === "paid") return true;
    // a late or repeated event never undoes a refund
    if (["refunded", "refund_pending", "partially_refunded"].includes(a.paymentStatus)) return true;
    tx.update(ref, {
      paymentStatus: "paid",
      paidAt: new Date().toISOString(),
      razorpayPaymentId: paymentId,
      amountPaid: amount / 100, // cash paid through Razorpay
      coinsUsed: Number(a.coinsReserved || 0), // MedCoins paid on top
      coinsReserved: 0,
      paidVia: via,
    });
    return true;
  });
}

exports.createRazorpayOrder = onCall(
  { secrets: [KEY_ID, KEY_SECRET] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please log in again to pay.");
    const appointmentId = String((request.data && request.data.appointmentId) || "");
    if (!appointmentId) throw new HttpsError("invalid-argument", "Booking not found.");
    const useCoins = !!(request.data && request.data.useCoins);

    const ref = db().collection("appointments").doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found.");
    const a = snap.data();
    if (a.patientUid !== uid) {
      throw new HttpsError("permission-denied", "You can only pay for your own bookings.");
    }
    if (a.paymentStatus === "paid") {
      throw new HttpsError("failed-precondition", "This booking is already paid.");
    }
    if (!PAYABLE_STATUSES.has(a.status)) {
      throw new HttpsError("failed-precondition",
        "You can pay once a provider has accepted your booking.");
    }
    // the price is worked out here from Firestore, not taken from the phone
    const p = await appointmentPrice(a);
    if (p.missing) {
      logger.error("price not set", { appointmentId, missing: p.missing });
      throw new HttpsError("failed-precondition",
        "The price for this service is not set yet. Please contact support.");
    }
    if (Number(a.price) !== p.price) {
      logger.warn("booking price corrected at payment", { appointmentId, sent: a.price, server: p.price });
      await ref.update({ ...p, priceStatus: "ok", priceCheckedAt: new Date().toISOString() });
      Object.assign(a, p);
    }
    const fullPaise = Math.round(p.price * 100); // paise
    if (fullPaise < 100) {
      throw new HttpsError("failed-precondition", "This booking has no valid price.");
    }

    // MedCoins (1 = ₹1): whole rupees. Coins already held for an earlier,
    // unpaid try count as available again.
    const held = Number(a.coinsReserved || 0);
    const available = (await wallet.balanceOf(uid)) + held;
    const coins = wallet.coinsToUse(available, Math.floor(fullPaise / 100), useCoins);

    // ---- paid fully with MedCoins: no Razorpay payment
    if (coins >= fullPaise / 100) {
      const split = await providerTransfer(appointmentId, a, fullPaise); // checks payouts
      await db().runTransaction(async (tx) => {
        const fresh = (await tx.get(ref)).data();
        if (fresh.paymentStatus === "paid") return;
        const held2 = Number(fresh.coinsReserved || 0);
        const bal = await wallet.balanceIn(tx, uid);
        const need = coins - held2;
        if (need > bal) throw new HttpsError("failed-precondition", "Not enough MedCoins.");
        if (need !== 0) {
          wallet.applyDelta(tx, uid, -need, {
            type: need > 0 ? "debit" : "release",
            reason: "Booking paid with MedCoins", refKind: "appointment", refId: appointmentId,
          });
        }
        tx.update(ref, {
          paymentStatus: "paid",
          paidAt: new Date().toISOString(),
          paidVia: "medcoins",
          amountPaid: 0,
          coinsUsed: coins,
          coinsReserved: 0,
          platformFee: split.platformFee / 100,
          providerShare: split.providerShare / 100,
          payoutAccountId: split.payoutAccountId,
          // no Razorpay payment holds the provider's share: it is sent from
          // the app's balance when the visit is completed
          coinTopUpPaise: split.providerShare,
          razorpayOrderId: null,
        });
      });
      return { paidWithCoins: true };
    }

    // ---- cash through Razorpay (minus any MedCoins)
    // paise to collect; Razorpay needs at least ₹1, so leave some cash if the
    // MedCoins would cover all but a few paise (prices with paise)
    if (fullPaise - coins * 100 < 100) coins = Math.max(0, coins - 1);
    const amount = fullPaise - coins * 100;
    const details = {
      keyId: KEY_ID.value(),
      amount,
      currency: "INR",
      description: serviceLabel(a),
      patientName: a.patientName || "",
      patientPhone: a.patientPhone || "",
    };

    // 10% app / 90% provider of what is collected (held until the visit is
    // completed); the provider's 90% of the MedCoin part is sent from the
    // app's balance at completion
    const split = await providerTransfer(appointmentId, a, amount);
    const coinShare = splitAmount(coins * 100);

    // Reuse the open order if nothing changed (retry after cancel)
    if (a.razorpayOrderId && a.razorpayOrderAmount === amount &&
        a.payoutAccountId === split.payoutAccountId && held === coins) {
      return { ...details, orderId: a.razorpayOrderId };
    }

    const auth = Buffer.from(`${KEY_ID.value()}:${KEY_SECRET.value()}`).toString("base64");
    const res = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount,
        currency: "INR",
        receipt: appointmentId.slice(0, 40),
        notes: { appointmentId, patientUid: uid },
        transfers: [split.transfer],
      }),
    });
    const order = await res.json();
    if (!res.ok || !order.id) {
      logger.error("Razorpay order failed", { appointmentId, status: res.status, order });
      throw new HttpsError("unavailable", "Payment could not be started. Please try again.");
    }

    await db().runTransaction(async (tx) => {
      const fresh = (await tx.get(ref)).data();
      const held2 = Number(fresh.coinsReserved || 0);
      const bal = await wallet.balanceIn(tx, uid);
      const need = coins - held2; // more coins to hold (or give back if negative)
      if (need > bal) throw new HttpsError("failed-precondition", "Not enough MedCoins.");
      if (need !== 0) {
        wallet.applyDelta(tx, uid, -need, {
          type: need > 0 ? "hold" : "release",
          reason: "MedCoins for a booking payment", refKind: "appointment", refId: appointmentId,
        });
      }
      tx.update(ref, {
        razorpayOrderId: order.id,
        razorpayOrderAmount: amount,
        paymentStatus: "pending",
        coinsReserved: coins,
        coinTopUpPaise: coinShare.provider,
        platformFee: (split.platformFee + coinShare.platform) / 100,
        providerShare: (split.providerShare + coinShare.provider) / 100,
        payoutAccountId: split.payoutAccountId,
      });
    });
    return { ...details, orderId: order.id };
  },
);

exports.verifyRazorpayPayment = onCall(
  { secrets: [KEY_SECRET] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please log in again.");
    const { appointmentId, orderId, paymentId, signature } = request.data || {};
    if (!appointmentId || !orderId || !paymentId || !signature) {
      throw new HttpsError("invalid-argument", "Payment details are missing.");
    }
    const snap = await db().collection("appointments").doc(String(appointmentId)).get();
    if (!snap.exists || snap.data().patientUid !== uid) {
      throw new HttpsError("permission-denied", "Booking not found.");
    }

    const expected = crypto
      .createHmac("sha256", KEY_SECRET.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
    if (!safeEqual(expected, signature)) {
      logger.warn("Razorpay signature mismatch", { appointmentId, orderId });
      throw new HttpsError("permission-denied", "Payment could not be verified.");
    }

    const ok = await markPaid(String(appointmentId), {
      orderId: String(orderId),
      paymentId: String(paymentId),
      amount: snap.data().razorpayOrderAmount || 0,
      via: "checkout",
    });
    if (!ok) throw new HttpsError("failed-precondition", "Payment does not match this booking.");
    return { paid: true };
  },
);

/** Razorpay dashboard -> Webhooks: URL of this function, events
 *  "payment.captured", "order.paid" and the Route product events
 *  ("product.route.*"), secret = RAZORPAY_WEBHOOK_SECRET. */
exports.razorpayWebhook = onRequest(
  { secrets: [WEBHOOK_SECRET] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }
    const signature = req.get("X-Razorpay-Signature") || "";
    const expected = crypto
      .createHmac("sha256", WEBHOOK_SECRET.value())
      .update(req.rawBody)
      .digest("hex");
    if (!safeEqual(expected, signature)) {
      res.status(400).send("Invalid signature");
      return;
    }

    const event = req.body || {};
    // Provider payout account activated / needs clarification / ...
    if (String(event.event || "").startsWith("product.route.") ||
        String(event.event || "").startsWith("account.")) {
      await updatePayoutStatusFromWebhook(event);
      res.status(200).send("ok");
      return;
    }
    const payment = event.payload && event.payload.payment && event.payload.payment.entity;
    if ((event.event === "payment.captured" || event.event === "order.paid") && payment) {
      const appointmentId = payment.notes && payment.notes.appointmentId;
      const rechargeId = payment.notes && payment.notes.rechargeId;
      if (rechargeId) {
        // chat recharge: same as the checkout confirmation, if the app closed first
        await applyRecharge(String(rechargeId), {
          orderId: payment.order_id,
          paymentId: payment.id,
          via: "webhook",
        });
      } else if (appointmentId) {
        await markPaid(String(appointmentId), {
          orderId: payment.order_id,
          paymentId: payment.id,
          amount: payment.amount,
          via: "webhook",
        });
      } else {
        logger.warn("Razorpay webhook without appointmentId", { id: payment.id });
      }
    }
    res.status(200).send("ok");
  },
);
