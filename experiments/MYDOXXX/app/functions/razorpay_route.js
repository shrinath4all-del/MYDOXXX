/**
 * Razorpay Route: split every booking payment between the app and the
 * provider who took the booking.
 *
 *   App (platform)  PLATFORM_COMMISSION_PCT (10%)
 *   Provider        the rest (90%), sent to their own Razorpay linked
 *                   account and held until the visit is completed
 *
 *   setupProviderPayouts       provider's bank details -> linked account
 *   refreshProviderPayoutStatus  re-reads the activation status
 *   settleBookingPayment       booking Completed -> release the held 90%;
 *                              Provider Absent / Cancelled / Declined
 *                              after payment -> full refund to the patient
 *                              (the provider's transfer is reversed)
 *
 * Razorpay docs: Route linked accounts (v2/accounts, stakeholders,
 * products), transfers via orders, modify settlement hold, refunds.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const wallet = require("./wallet");

const KEY_ID = defineSecret("RAZORPAY_KEY_ID");
const KEY_SECRET = defineSecret("RAZORPAY_KEY_SECRET");

/** The app's share of every booking payment, in percent. */
const PLATFORM_COMMISSION_PCT = 10;

const db = () => admin.firestore();

// role -> provider collection and Razorpay business sub-category
const ROLES = {
  doctor: { collection: "doctors", subcategory: "doctors" },
  therapist: { collection: "therapists", subcategory: "health_practitioners_medical_services" },
  nurse: { collection: "nurses", subcategory: "health_practitioners_medical_services" },
  technician: { collection: "technicians", subcategory: "lab" },
};

// Booking statuses after which a paid booking is refunded
const REFUND_STATUSES = new Set(["Provider Absent", "Cancelled", "Declined"]);

/** Provider collection of a booking (same rule as the app). */
function providerCollectionOf(a) {
  if (a.isTherapistRequest || a.roleTarget === "therapist") return "therapists";
  if (a.isNurseRequest || a.roleTarget === "nurse") return "nurses";
  if (a.isTechnicianRequest || a.roleTarget === "technician") return "technicians";
  return "doctors";
}

/** Split [amount] (paise): app keeps the commission, provider the rest. */
function splitAmount(amount) {
  const platform = Math.round((amount * PLATFORM_COMMISSION_PCT) / 100);
  return { platform, provider: amount - platform };
}

class RazorpayError extends Error {
  constructor(status, body) {
    const d = (body && body.error && body.error.description) || `HTTP ${status}`;
    super(d);
    this.status = status;
    this.body = body;
  }
}

async function razorpay(method, path, body) {
  const auth = Buffer.from(`${KEY_ID.value()}:${KEY_SECRET.value()}`).toString("base64");
  const res = await fetch(`https://api.razorpay.com${path}`, {
    method,
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new RazorpayError(res.status, json);
  return json;
}

// ------------------------------------------------------------ onboarding

const PAN = /^[A-Za-z]{5}\d{4}[A-Za-z]$/;
const IFSC = /^[A-Za-z]{4}0[A-Za-z0-9]{6}$/;
const ACCOUNT = /^\d{9,18}$/;
const PIN = /^\d{6}$/;
const STATE = /^[A-Za-z]{2}$/;

function readDetails(data) {
  const d = {};
  const str = (k) => String((data && data[k]) || "").trim();
  d.legalName = str("legalName");
  d.email = str("email").toLowerCase();
  d.phone = str("phone").replace(/\D/g, "").slice(-10);
  d.pan = str("pan").toUpperCase();
  d.accountNumber = str("accountNumber").replace(/\s/g, "");
  d.ifsc = str("ifsc").toUpperCase();
  d.beneficiaryName = str("beneficiaryName") || d.legalName;
  d.street = str("street");
  d.city = str("city");
  d.state = str("state").toUpperCase();
  d.postalCode = str("postalCode");

  const problems = [];
  if (d.legalName.length < 4) problems.push("full name as on PAN");
  if (!/^\S+@\S+\.\S+$/.test(d.email)) problems.push("email");
  if (d.phone.length !== 10) problems.push("10-digit mobile number");
  if (!PAN.test(d.pan) || d.pan[3] !== "P") problems.push("personal PAN (4th letter P)");
  if (!ACCOUNT.test(d.accountNumber)) problems.push("bank account number");
  if (!IFSC.test(d.ifsc)) problems.push("IFSC code");
  if (d.street.length < 10) problems.push("address (at least 10 characters)");
  if (d.city.length < 2) problems.push("city");
  if (!STATE.test(d.state)) problems.push("state");
  if (!PIN.test(d.postalCode)) problems.push("6-digit PIN code");
  if (problems.length) {
    throw new HttpsError("invalid-argument", `Please check: ${problems.join(", ")}.`);
  }
  return d;
}

async function roleOf(uid) {
  const user = await db().collection("users").doc(uid).get();
  const role = user.exists ? user.data().role : null;
  if (!ROLES[role]) {
    throw new HttpsError("permission-denied",
      "Only doctors, physios, nurses and technicians can set up payouts.");
  }
  return role;
}

function payoutFields(product, extra = {}) {
  const requirements = (product.requirements || [])
    .map((r) => r.field_reference)
    .filter(Boolean);
  return {
    payoutStatus: product.activation_status || "requested",
    payoutRequirements: requirements,
    payoutUpdatedAt: new Date().toISOString(),
    ...extra,
  };
}

function friendly(e) {
  if (e instanceof HttpsError) return e;
  if (e instanceof RazorpayError) {
    logger.error("Razorpay Route error", { status: e.status, body: e.body });
    return new HttpsError("failed-precondition", `Razorpay: ${e.message}`);
  }
  logger.error("Payout setup failed", e);
  return new HttpsError("internal", "Payout setup failed. Please try again.");
}

exports.setupProviderPayouts = onCall(
  { secrets: [KEY_ID, KEY_SECRET] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please log in again.");
    try {
      const role = await roleOf(uid);
      const { collection, subcategory } = ROLES[role];
      const d = readDetails(request.data);
      const ref = db().collection(collection).doc(uid);
      const provider = (await ref.get()).data() || {};

      // 1. Linked account (reused if an earlier attempt created it)
      let accountId = provider.payoutAccountId;
      if (!accountId) {
        const account = await razorpay("POST", "/v2/accounts", {
          email: d.email,
          phone: d.phone,
          type: "route",
          reference_id: uid,
          legal_business_name: d.legalName,
          business_type: "individual",
          contact_name: d.legalName,
          profile: {
            category: "healthcare",
            subcategory,
            addresses: {
              registered: {
                street1: d.street.slice(0, 100),
                street2: d.street.slice(100, 200) || d.city,
                city: d.city,
                state: d.state,
                postal_code: Number(d.postalCode),
                country: "IN",
              },
            },
          },
          legal_info: { pan: d.pan },
        });
        accountId = account.id;
        await ref.set({ payoutAccountId: accountId }, { merge: true });

        // 2. Stakeholder (the provider) with PAN
        await razorpay("POST", `/v2/accounts/${accountId}/stakeholders`, {
          name: d.legalName,
          email: d.email,
          addresses: {
            residential: {
              street: d.street,
              city: d.city,
              state: d.state,
              postal_code: d.postalCode,
              country: "IN",
            },
          },
          kyc: { pan: d.pan },
        });
      }

      // 3. Route product, then 4. the bank account money is settled to
      let productId = provider.payoutProductId;
      if (!productId) {
        const product = await razorpay("POST", `/v2/accounts/${accountId}/products`, {
          product_name: "route",
          tnc_accepted: true,
        });
        productId = product.id;
        await ref.set({ payoutProductId: productId }, { merge: true });
      }
      const product = await razorpay("PATCH", `/v2/accounts/${accountId}/products/${productId}`, {
        settlements: {
          account_number: d.accountNumber,
          ifsc_code: d.ifsc,
          beneficiary_name: d.beneficiaryName,
        },
        tnc_accepted: true,
      });

      // Only masked details are kept in Firestore
      const fields = payoutFields(product, {
        payoutBankLast4: d.accountNumber.slice(-4),
        payoutIfsc: d.ifsc,
        payoutName: d.legalName,
      });
      await ref.set(fields, { merge: true });
      return { status: fields.payoutStatus, requirements: fields.payoutRequirements };
    } catch (e) {
      throw friendly(e);
    }
  },
);

exports.refreshProviderPayoutStatus = onCall(
  { secrets: [KEY_ID, KEY_SECRET] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please log in again.");
    try {
      const role = await roleOf(uid);
      const ref = db().collection(ROLES[role].collection).doc(uid);
      const p = (await ref.get()).data() || {};
      if (!p.payoutAccountId || !p.payoutProductId) return { status: "not_started" };
      const product = await razorpay("GET",
        `/v2/accounts/${p.payoutAccountId}/products/${p.payoutProductId}`);
      const fields = payoutFields(product);
      await ref.set(fields, { merge: true });
      return { status: fields.payoutStatus, requirements: fields.payoutRequirements };
    } catch (e) {
      throw friendly(e);
    }
  },
);

/** Webhook helper: a Route product/account event changed a provider's
 *  activation status. */
async function updatePayoutStatusFromWebhook(event) {
  const entity = (event.payload &&
    (event.payload.merchant_product || event.payload.account || {}).entity) || {};
  const accountId = event.account_id || entity.account_id || entity.merchant_id || entity.id;
  const status = entity.activation_status ||
    (String(event.event || "").startsWith("product.route.")
      ? String(event.event).slice("product.route.".length) : null);
  if (!accountId || !status) return false;
  for (const { collection } of Object.values(ROLES)) {
    const snap = await db().collection(collection)
      .where("payoutAccountId", "==", accountId).limit(1).get();
    if (!snap.empty) {
      await snap.docs[0].ref.set({
        payoutStatus: status,
        payoutUpdatedAt: new Date().toISOString(),
      }, { merge: true });
      return true;
    }
  }
  return false;
}

// -------------------------------------------------------- order split

/** Transfer for a booking order: the provider's 90%, held until the visit
 *  is completed. Throws if the provider can't receive payouts yet. */
async function providerTransfer(appointmentId, a, amount) {
  const collection = providerCollectionOf(a);
  const providerUid = String(a.doctorUid || "");
  const provider = providerUid
    ? (await db().collection(collection).doc(providerUid).get()).data() || {}
    : {};
  if (!provider.payoutAccountId || provider.payoutStatus !== "activated") {
    const name = a.doctorName || "This provider";
    throw new HttpsError("failed-precondition",
      `${name} has not finished setting up payouts yet, so this booking can't be paid online right now. Please try again later.`);
  }
  const { platform, provider: share } = splitAmount(amount);
  return {
    platformFee: platform,
    providerShare: share,
    payoutAccountId: provider.payoutAccountId,
    transfer: {
      account: provider.payoutAccountId,
      amount: share,
      currency: "INR",
      on_hold: true,
      notes: { appointmentId, providerUid },
      linked_account_notes: ["appointmentId"],
    },
  };
}

// ------------------------------------------------- release / refund

async function transferIdFor(a) {
  if (a.payoutTransferId) return a.payoutTransferId;
  if (!a.razorpayPaymentId) return null;
  const list = await razorpay("GET", `/v1/payments/${a.razorpayPaymentId}/transfers`);
  const t = (list.items || []).find((x) => x.recipient === a.payoutAccountId) ||
    (list.items || [])[0];
  return t ? t.id : null;
}

/** Gives MedCoins back to the patient's wallet (once per booking). */
async function creditBookingCoins(appointmentId, ref, { field, flag, type, reason }) {
  await db().runTransaction(async (tx) => {
    const a = (await tx.get(ref)).data() || {};
    const coins = Number(a[field] || 0);
    if (!(coins > 0) || a[flag]) return;
    wallet.applyDelta(tx, a.patientUid, coins, {
      type, reason, refKind: "appointment", refId: appointmentId,
    });
    tx.update(ref, { [flag]: true, ...(field === "coinsReserved" ? { coinsReserved: 0 } : {}) });
  });
}

exports.settleBookingPayment = onDocumentUpdated(
  { document: "appointments/{id}", secrets: [KEY_ID, KEY_SECRET] },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const ref = event.data.after.ref;
    const statusChanged = before.status !== after.status;

    try {
      // A booking that was never paid ended: give back the MedCoins held for it
      if (REFUND_STATUSES.has(after.status) && statusChanged &&
          after.paymentStatus !== "paid" && Number(after.coinsReserved) > 0) {
        await creditBookingCoins(event.params.id, ref, {
          field: "coinsReserved", flag: "coinsReleased", type: "release",
          reason: "Booking was not completed",
        });
        return;
      }

      if (after.paymentStatus !== "paid" || !after.payoutAccountId) return;

      // Visit done: release the provider's 90%
      if (after.status === "Completed" && !after.payoutReleased &&
          (statusChanged || before.paymentStatus !== "paid")) {
        const update = {};
        // the part paid through Razorpay: release the held transfer
        if (after.razorpayPaymentId) {
          const transferId = await transferIdFor(after);
          if (!transferId) {
            logger.warn("No transfer to release yet", { id: event.params.id });
            return;
          }
          await razorpay("PATCH", `/v1/transfers/${transferId}`, { on_hold: false });
          update.payoutTransferId = transferId;
        }
        // the part paid with MedCoins: no Razorpay payment holds it, so the
        // provider's share of it is sent from the app's balance
        const topUp = Number(after.coinTopUpPaise || 0);
        if (topUp > 0 && !after.coinTopUpTransferId) {
          const t = await razorpay("POST", "/v1/transfers", {
            account: after.payoutAccountId,
            amount: topUp,
            currency: "INR",
            notes: { appointmentId: event.params.id, part: "medcoins" },
          });
          update.coinTopUpTransferId = t.id;
        }
        await ref.update({
          ...update,
          payoutReleased: true,
          payoutReleasedAt: new Date().toISOString(),
        });
        return;
      }

      // Visit did not happen: refund the patient in full (cash back to the
      // payment method, MedCoins back to the wallet) and take the provider's
      // held transfer back
      if (REFUND_STATUSES.has(after.status) && statusChanged && !after.refundId) {
        let refundId = "medcoins";
        if (after.razorpayPaymentId) {
          const refund = await razorpay("POST",
            `/v1/payments/${after.razorpayPaymentId}/refund`, {
              amount: after.razorpayOrderAmount,
              reverse_all: 1,
              notes: { appointmentId: event.params.id, reason: after.status },
            });
          refundId = refund.id;
        }
        await creditBookingCoins(event.params.id, ref, {
          field: "coinsUsed", flag: "coinsRefunded", type: "credit",
          reason: "Booking refunded: " + after.status,
        });
        await ref.update({
          paymentStatus: "refunded",
          refundId,
          refundedAt: new Date().toISOString(),
        });
      }
    } catch (e) {
      logger.error("Booking settlement failed", {
        id: event.params.id,
        status: after.status,
        error: e.message,
        body: e.body,
      });
      await ref.update({ settlementError: String(e.message).slice(0, 300) });
    }
  },
);

module.exports.providerTransfer = providerTransfer;
module.exports.updatePayoutStatusFromWebhook = updatePayoutStatusFromWebhook;
module.exports.splitAmount = splitAmount;
module.exports.PLATFORM_COMMISSION_PCT = PLATFORM_COMMISSION_PCT;
