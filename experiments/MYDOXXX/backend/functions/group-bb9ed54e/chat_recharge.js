/**
 * Paid chat recharge.
 *
 * After a consultation ends the chat is open for 24 hours with 10 free
 * messages for the patient. When that runs out the patient can recharge with
 * a plan of 25 messages (days, messages and price come from
 * `chat_recharge_plans` in Firestore, never from the phone). The plan with
 * kind "single" (₹200) is the single message after the consultation: it lets
 * the patient send one message and keeps the chat open a day for the reply. The whole amount goes to the app, and the patient
 * can pay all or part of it with MedCoins (see wallet.js).
 *
 *   createChatRechargeOrder      -> Razorpay order for a plan (or paid fully
 *                                   with MedCoins, no Razorpay)
 *   verifyChatRechargePayment    -> checks the checkout signature, applies it
 *   applyRecharge                -> also used by the Razorpay webhook (backup)
 *   refundUnansweredChatRecharges (every 15 min)
 *                                -> the clock starts when the PATIENT writes
 *                                   after paying: if the provider has not
 *                                   replied within 4 hours of that message,
 *                                   the recharge goes back to the patient as
 *                                   MedCoins
 *
 * Firestore collections:
 *   chat_recharge_plans/{id}     { days, price, messages, active, order,
 *                                  kind ("single" for the one-message plan) }
 *   chat_recharges/{id}          one per purchase (status: created, paid,
 *                                settled, refunded_to_wallet, abandoned)
 *   wallets, wallet_transactions (wallet.js)
 *   chats/{chatId}               accessEpoch, patientMsgsUsed, bonusMsgs,
 *                                paidUntil (see lib/utils/chat_access.dart)
 */
const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const wallet = require("./wallet");

const KEY_ID = defineSecret("RAZORPAY_KEY_ID");
const KEY_SECRET = defineSecret("RAZORPAY_KEY_SECRET");

const db = () => admin.firestore();
const DAY_MS = 24 * 60 * 60 * 1000;
const BASE_WINDOW_MS = DAY_MS;
const ABANDONED_AFTER_MS = 60 * 60 * 1000;
/** Free messages in each chat window (lib/utils/chat_access.dart). */
const BASE_MESSAGES = 10;

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** The chat id is "<patientUid>_<providerUid>". */
function parties(chatId) {
  const p = String(chatId || "").split("_");
  if (p.length !== 2 || !p[0] || !p[1]) return null;
  return { patientUid: p[0], providerUid: p[1] };
}

/** When the latest finished consultation between the two ended (ms), or null. */
async function consultationEnd(patientUid, providerUid) {
  const snap = await db().collection("appointments")
    .where("patientUid", "==", patientUid)
    .where("doctorUid", "==", providerUid)
    .get();
  let latest = null;
  for (const d of snap.docs) {
    const a = d.data();
    if (a.status !== "Completed") continue;
    const t = wallet.istMs(a.completedAt);
    if (!Number.isNaN(t) && (latest === null || t > latest)) latest = t;
  }
  return latest;
}

/**
 * What a paid recharge does to the chat: the counters of this consultation's
 * window (a new consultation starts a fresh one) plus the plan's messages,
 * and the end of the chat time moved by the plan's days (from the current
 * end, or from now if the time already ran out). The single-message plan
 * makes sure exactly one more message is left (unused free messages are
 * not taken away).
 */
function computeApply(chat, plan, endMs, nowMs) {
  const sameWindow = wallet.istMs(chat.accessEpoch) === endMs;
  const used = sameWindow ? Number(chat.patientMsgsUsed || 0) : 0;
  const bonusBefore = sameWindow ? Number(chat.bonusMsgs || 0) : 0;
  const paidBeforeMs = sameWindow ? wallet.istMs(chat.paidUntil) : NaN;
  const currentEnd = Math.max(endMs + BASE_WINDOW_MS, Number.isNaN(paidBeforeMs) ? 0 : paidBeforeMs);
  const newEnd = Math.max(nowMs, currentEnd) + plan.days * DAY_MS;
  const bonus = plan.single
    ? Math.max(bonusBefore, used + plan.messages - BASE_MESSAGES)
    : bonusBefore + plan.messages;
  return {
    epoch: new Date(endMs).toISOString(),
    used,
    bonus,
    bonusBefore,
    paidBeforeMs,
    newEnd,
  };
}

/** Writes the chat counters and marks the recharge paid (inside a transaction). */
function writeApply(tx, chatRef, rechargeRef, c, extra) {
  tx.set(chatRef, {
    accessEpoch: c.epoch,
    patientMsgsUsed: c.used,
    bonusMsgs: c.bonus,
    paidUntil: new Date(c.newEnd).toISOString(),
  }, { merge: true });
  tx.update(rechargeRef, {
    status: "paid",
    paidAt: new Date().toISOString(),
    epoch: c.epoch,
    paidUntilBefore: Number.isNaN(c.paidBeforeMs) ? null : new Date(c.paidBeforeMs).toISOString(),
    paidUntilAfter: new Date(c.newEnd).toISOString(),
    bonusAdded: c.bonus - c.bonusBefore,
    ...extra,
  });
}

exports.createChatRechargeOrder = onCall(
  { secrets: [KEY_ID, KEY_SECRET] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please log in again to pay.");
    const chatId = String((request.data && request.data.chatId) || "");
    const planId = String((request.data && request.data.planId) || "");
    const useCoins = !!(request.data && request.data.useCoins);
    const who = parties(chatId);
    if (!who || who.patientUid !== uid) {
      throw new HttpsError("permission-denied", "Only the patient can recharge this chat.");
    }
    const planSnap = await db().collection("chat_recharge_plans").doc(planId).get();
    const plan = planSnap.exists ? planSnap.data() : null;
    const price = plan ? Math.round(Number(plan.price)) : 0;
    const days = plan ? Number(plan.days) : 0;
    const messages = plan ? Number(plan.messages) : 0;
    const single = !!plan && plan.kind === "single";
    if (!plan || plan.active === false || !(price >= 1) || !(days >= 1)) {
      throw new HttpsError("failed-precondition",
        "This plan is not available. Please contact support.");
    }
    const endMs = await consultationEnd(who.patientUid, who.providerUid);
    if (endMs === null) {
      throw new HttpsError("failed-precondition",
        "Chat can be recharged after a consultation has ended.");
    }

    const coins = wallet.coinsToUse(await wallet.balanceOf(uid), price, useCoins);
    const ref = db().collection("chat_recharges").doc();
    const base = {
      rechargeId: ref.id,
      chatId,
      patientUid: who.patientUid,
      providerUid: who.providerUid,
      planId,
      planDays: days,
      planMessages: messages,
      planKind: single ? "single" : "",
      price,
      createdAt: new Date().toISOString(),
    };
    const chatRef = db().collection("chats").doc(chatId);

    // Paid fully with MedCoins: no Razorpay
    if (coins >= price) {
      await db().runTransaction(async (tx) => {
        const bal = await wallet.balanceIn(tx, uid);
        const chat = (await tx.get(chatRef)).data() || {};
        if (bal < price) throw new HttpsError("failed-precondition", "Not enough MedCoins.");
        const c = computeApply(chat, { days, messages, single }, endMs, Date.now());
        wallet.applyDelta(tx, uid, -price, {
          type: "debit", reason: "Chat recharge", refKind: "chat_recharge", refId: ref.id,
        });
        tx.set(ref, { ...base, status: "created", coinsUsed: price, razorpayOrderId: null });
        writeApply(tx, chatRef, ref, c, { paidVia: "medcoins", coinsUsed: price, cashPaid: 0 });
      });
      return { paidWithCoins: true, rechargeId: ref.id };
    }

    // Cash part through Razorpay, the rest (if any) reserved from MedCoins
    const cash = price - coins;
    const amount = cash * 100; // paise
    const auth = Buffer.from(`${KEY_ID.value()}:${KEY_SECRET.value()}`).toString("base64");
    const res = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount,
        currency: "INR",
        receipt: ref.id.slice(0, 40),
        notes: { type: "chat_recharge", rechargeId: ref.id, patientUid: uid, chatId },
      }),
    });
    const order = await res.json();
    if (!res.ok || !order.id) {
      logger.error("Razorpay chat recharge order failed", { status: res.status, order });
      throw new HttpsError("unavailable", "Payment could not be started. Please try again.");
    }

    await db().runTransaction(async (tx) => {
      if (coins > 0) {
        const bal = await wallet.balanceIn(tx, uid);
        if (bal < coins) throw new HttpsError("failed-precondition", "Not enough MedCoins.");
        wallet.applyDelta(tx, uid, -coins, {
          type: "hold", reason: "Chat recharge (part paid with MedCoins)",
          refKind: "chat_recharge", refId: ref.id,
        });
      }
      tx.set(ref, {
        ...base,
        amount,
        razorpayOrderId: order.id,
        coinsReserved: coins,
        status: "created",
      });
    });

    const user = (await db().collection("users").doc(uid).get()).data() || {};
    return {
      keyId: KEY_ID.value(),
      orderId: order.id,
      amount,
      currency: "INR",
      rechargeId: ref.id,
      description: single
        ? "Single message to your doctor"
        : `Chat recharge · ${days} day${days === 1 ? "" : "s"}`,
      patientName: user.name || "",
      patientPhone: user.phone || "",
    };
  },
);

/**
 * Marks the recharge paid and gives the patient the extra time and messages.
 * Safe to run twice (checkout confirmation and webhook both call it).
 */
async function applyRecharge(rechargeId, { orderId, paymentId, via }) {
  const rechargeRef = db().collection("chat_recharges").doc(rechargeId);
  const first = await rechargeRef.get();
  if (!first.exists) return false;
  const r0 = first.data();
  if (r0.razorpayOrderId !== orderId) return false;
  const endMs = await consultationEnd(r0.patientUid, r0.providerUid);
  if (endMs === null) return false;

  return db().runTransaction(async (tx) => {
    const snap = await tx.get(rechargeRef);
    const r = snap.data();
    if (r.status !== "created") return true; // already applied (or refunded)
    const chatRef = db().collection("chats").doc(r.chatId);
    const chat = (await tx.get(chatRef)).data() || {};
    const c = computeApply(chat, {
      days: r.planDays, messages: r.planMessages, single: r.planKind === "single",
    }, endMs, Date.now());
    writeApply(tx, chatRef, rechargeRef, c, {
      razorpayPaymentId: paymentId,
      paidVia: via,
      coinsUsed: Number(r.coinsReserved || 0),
      coinsReserved: 0,
      cashPaid: r.price - Number(r.coinsReserved || 0),
    });
    return true;
  });
}
exports.applyRecharge = applyRecharge;

exports.verifyChatRechargePayment = onCall(
  { secrets: [KEY_SECRET] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please log in again.");
    const { rechargeId, orderId, paymentId, signature } = request.data || {};
    if (!rechargeId || !orderId || !paymentId || !signature) {
      throw new HttpsError("invalid-argument", "Payment details are missing.");
    }
    const snap = await db().collection("chat_recharges").doc(String(rechargeId)).get();
    if (!snap.exists || snap.data().patientUid !== uid) {
      throw new HttpsError("permission-denied", "Recharge not found.");
    }
    const expected = crypto
      .createHmac("sha256", KEY_SECRET.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
    if (!safeEqual(expected, signature)) {
      logger.warn("chat recharge signature mismatch", { rechargeId, orderId });
      throw new HttpsError("permission-denied", "Payment could not be verified.");
    }
    const ok = await applyRecharge(String(rechargeId), {
      orderId: String(orderId),
      paymentId: String(paymentId),
      via: "checkout",
    });
    if (!ok) throw new HttpsError("failed-precondition", "Payment does not match this recharge.");
    return { paid: true };
  },
);

/** Chat messages as { senderUid, atMs } (server time). */
async function recentMessages(chatId) {
  const snap = await db().collection("chats").doc(chatId).collection("messages")
    .orderBy("timestamp", "desc").limit(150).get();
  return snap.docs
    .map((d) => d.data())
    .filter((m) => m.timestamp && typeof m.timestamp.toMillis === "function")
    .map((m) => ({ senderUid: m.senderUid, atMs: m.timestamp.toMillis() }));
}

exports.refundUnansweredChatRecharges = onSchedule(
  { schedule: "every 15 minutes", timeZone: "Asia/Kolkata" },
  async () => {
    const now = Date.now();
    let refunded = 0;
    let answered = 0;

    // 1. paid recharges: the provider must answer the patient's message
    const paid = await db().collection("chat_recharges").where("status", "==", "paid").get();
    for (const doc of paid.docs) {
      const r = doc.data();
      const paidAtMs = Date.parse(r.paidAt || "");
      if (Number.isNaN(paidAtMs)) continue;
      const decision = wallet.chatRechargeDecision({
        messages: await recentMessages(r.chatId),
        patientUid: r.patientUid,
        providerUid: r.providerUid,
        paidAtMs,
        nowMs: now,
      });
      if (decision === "wait") continue;
      if (decision === "answered") {
        await doc.ref.update({ status: "settled", settledAt: new Date().toISOString() });
        answered++;
        continue;
      }

      await db().runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (fresh.data().status !== "paid") return;
        const chatRef = db().collection("chats").doc(r.chatId);
        const chat = (await tx.get(chatRef)).data() || {};
        // take the extra time and messages back, if nothing was added since
        if (chat.accessEpoch && wallet.istMs(chat.paidUntil) === wallet.istMs(r.paidUntilAfter)) {
          const added = Number(r.bonusAdded ?? r.planMessages);
          tx.set(chatRef, {
            bonusMsgs: Math.max(0, Number(chat.bonusMsgs || 0) - added),
            paidUntil: r.paidUntilBefore || admin.firestore.FieldValue.delete(),
          }, { merge: true });
        }
        // the whole amount (cash and MedCoins) goes back as MedCoins
        wallet.applyDelta(tx, r.patientUid, Math.round(r.price), {
          type: "credit",
          reason: "Chat recharge: the provider did not reply within 4 hours of your message",
          refKind: "chat_recharge",
          refId: doc.id,
        });
        tx.update(doc.ref, {
          status: "refunded_to_wallet",
          refundedAt: new Date().toISOString(),
          refundedCoins: Math.round(r.price),
          refundReason: "no provider reply within 4 hours of the patient's message",
        });
      });
      refunded++;
    }

    // 2. orders never paid: give reserved MedCoins back
    const open = await db().collection("chat_recharges").where("status", "==", "created").get();
    let released = 0;
    for (const doc of open.docs) {
      const r = doc.data();
      const made = Date.parse(r.createdAt || "");
      if (!(Number(r.coinsReserved) > 0) || Number.isNaN(made) || now - made < ABANDONED_AFTER_MS) continue;
      await db().runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        const f = fresh.data();
        if (f.status !== "created" || !(Number(f.coinsReserved) > 0)) return;
        wallet.applyDelta(tx, f.patientUid, Number(f.coinsReserved), {
          type: "release", reason: "Chat recharge was not completed",
          refKind: "chat_recharge", refId: doc.id,
        });
        tx.update(doc.ref, { status: "abandoned", coinsReserved: 0 });
      });
      released++;
    }
    logger.info("chat recharge check", {
      paid: paid.size, answered, refunded, released,
    });
  },
);

exports.computeApply = computeApply;
