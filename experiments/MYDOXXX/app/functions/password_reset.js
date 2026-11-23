/**
 * Password reset links are valid for 15 minutes.
 *
 * Firebase sends the "set your password" email (agency logins created by the
 * admin, and "Forgot password?" for everyone) and its own link would work
 * for an hour. The app's reset page asks here first and refuses a link
 * older than 15 minutes, so the person requests a new one.
 *
 *   passwordReset({action: "sent",  email})  the app just sent a link
 *   passwordReset({action: "check", email})  { ok, expired, minutesLeft }
 *
 * Only the time of the newest link per email is kept
 * (password_resets/{email}); nothing about the account is returned.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const VALID_MINUTES = 15;
const MIN_MS = 60 * 1000;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Whether a link sent at [sentAt] (ms) may still be used at [now]. */
function freshness(sentAt, now) {
  // no record (sent before this check existed): Firebase's own expiry applies
  if (!Number.isFinite(sentAt)) return { ok: true, expired: false, minutesLeft: null };
  const left = sentAt + VALID_MINUTES * MIN_MS - now;
  return left > 0
    ? { ok: true, expired: false, minutesLeft: Math.ceil(left / MIN_MS) }
    : { ok: false, expired: true, minutesLeft: 0 };
}

const passwordReset = onCall(async (req) => {
  const action = String(req.data?.action || "");
  const email = String(req.data?.email || "").trim().toLowerCase();
  if (!EMAIL.test(email) || email.length > 200) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  const ref = admin.firestore().collection("password_resets").doc(email);
  if (action === "sent") {
    await ref.set({ sentAt: Date.now() });
    return { ok: true, validMinutes: VALID_MINUTES };
  }
  if (action === "check") {
    const snap = await ref.get();
    return freshness(snap.exists ? Number(snap.data().sentAt) : NaN, Date.now());
  }
  throw new HttpsError("invalid-argument", "Unknown action.");
});

module.exports = { passwordReset, freshness, VALID_MINUTES };
