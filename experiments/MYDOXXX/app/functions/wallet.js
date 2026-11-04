/**
 * MedCoins wallet: money returned to a patient (for example a chat recharge
 * the provider did not answer) and spent again on the next payment.
 * 1 MedCoin = ₹1. Only the server writes wallets.
 *
 *   wallets/{patientUid}         { balance }
 *   wallet_transactions/{id}     { patientUid, type, coins, reason, refKind,
 *                                  refId, createdAt }
 *     type: credit (refund), hold (reserved for an unpaid order),
 *           release (a hold given back), debit (spent)
 *
 * The functions at the top are plain (no Firestore) so they can be tested.
 */
const admin = require("firebase-admin");

const db = () => admin.firestore();

/** Hours a provider has to answer a paid chat message before the refund. */
const ANSWER_WITHIN_MS = 4 * 60 * 60 * 1000;

/**
 * Client times are saved without a zone ("2026-10-26T10:00:00"): they are
 * Indian time. Server times end in "Z". Returns milliseconds, or NaN.
 */
function istMs(iso) {
  const s = String(iso || "");
  if (!s) return NaN;
  const hasZone = /([zZ]|[+-]\d{2}:?\d{2})$/.test(s);
  return Date.parse(hasZone ? s : `${s}+05:30`);
}

/**
 * How many MedCoins a payment of [price] rupees uses when the patient asks to
 * spend them: all they have, but never more than the price.
 */
function coinsToUse(balance, price, useCoins) {
  if (!useCoins) return 0;
  const b = Math.max(0, Math.floor(Number(balance) || 0));
  return Math.min(b, Math.max(0, Math.round(Number(price) || 0)));
}

/**
 * Decides what to do with a paid chat recharge. [messages] are the chat
 * messages as { senderUid, atMs }.
 *   "wait"     nothing to answer yet, or the 4 hours are not over
 *   "answered" the provider replied within 4 hours of the patient's message
 *   "refund"   the patient wrote and the provider did not reply within 4 hours
 * The clock starts at the patient's first message after paying (not at the
 * payment).
 */
function chatRechargeDecision({ messages, patientUid, providerUid, paidAtMs, nowMs }) {
  const sorted = [...messages].sort((a, b) => a.atMs - b.atMs);
  const first = sorted.find((m) => m.senderUid === patientUid && m.atMs > paidAtMs);
  if (!first) return "wait";
  const deadline = first.atMs + ANSWER_WITHIN_MS;
  const answered = sorted.some((m) =>
    m.senderUid === providerUid && m.atMs > first.atMs && m.atMs <= deadline);
  if (answered) return "answered";
  return nowMs >= deadline ? "refund" : "wait";
}

// ------------------------------------------------ Firestore (in a transaction)

const walletRef = (uid) => db().collection("wallets").doc(uid);

/** Current MedCoins (read inside the transaction before any write). */
async function balanceIn(tx, uid) {
  const d = (await tx.get(walletRef(uid))).data();
  return Math.floor(Number(d && d.balance) || 0);
}

/** Outside a transaction (to decide how much to offer). */
async function balanceOf(uid) {
  const d = (await walletRef(uid).get()).data();
  return Math.floor(Number(d && d.balance) || 0);
}

/**
 * Changes the balance by [delta] coins and records why. The caller has
 * already read the balance in this transaction and checked it covers a debit.
 */
function applyDelta(tx, uid, delta, { type, reason, refKind, refId }) {
  tx.set(walletRef(uid), {
    patientUid: uid,
    balance: admin.firestore.FieldValue.increment(delta),
    updatedAt: new Date().toISOString(),
  }, { merge: true });
  const t = db().collection("wallet_transactions").doc();
  tx.set(t, {
    transactionId: t.id,
    patientUid: uid,
    type,
    coins: Math.abs(delta),
    reason,
    refKind,
    refId,
    createdAt: new Date().toISOString(),
  });
}

module.exports = {
  ANSWER_WITHIN_MS,
  istMs,
  coinsToUse,
  chatRechargeDecision,
  balanceIn,
  balanceOf,
  applyDelta,
};
