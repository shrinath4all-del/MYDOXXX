/**
 * Care Physician Agency Control Room (handover v1) - server side.
 *
 *   onDutyCreated        writes the duty's money shares from the agency
 *                        split (doctor 80 / agency 15 / app 5 by default;
 *                        the app share absorbs rounding)
 *   markAbsentDuties     every 15 min: a duty still not checked in 4 h after
 *                        its start becomes 'absent'
 *
 * Late (start + 15 min, no check-in) is worked out live on the screens.
 */
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const db = () => admin.firestore();
const ABSENT_AFTER_MS = 4 * 60 * 60 * 1000;

/** Doctor / agency / app shares of a hospital rate (₹, whole rupees). */
function splitDuty(hospitalRate, agency) {
  const rate = Math.round(Number(hospitalRate) || 0);
  const doctorPct = Number(agency.splitDoctorPct ?? 80);
  const agencyPct = Number(agency.splitAgencyPct ?? 15);
  const doctorPay = Math.round((rate * doctorPct) / 100);
  const agencyShare = Math.round((rate * agencyPct) / 100);
  return { doctorPay, agencyShare, appShare: rate - doctorPay - agencyShare };
}

const toMillis = (v) => (v && typeof v.toMillis === "function" ? v.toMillis()
  : (v ? Date.parse(v) : NaN));

/** Whether a duty should now be marked absent. */
function isAbsentNow(duty, nowMs) {
  if ((duty.status || "scheduled") !== "scheduled" || duty.checkInAt) return false;
  const start = toMillis(duty.shiftStart);
  return Number.isFinite(start) && nowMs > start + ABSENT_AFTER_MS;
}

/** 'yyyy-MM-dd' in Asia/Kolkata. */
function istDateKey(ms) {
  return new Date(ms + 330 * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * Rates of a new duty: the agency's base rate, and what the hospital is
 * billed. An emergency locum is billed app_settings/pricing
 * .emergencyLocumHikePct (20) more. Duties from older apps have no baseRate:
 * their hospitalRate is the agency's rate.
 */
function dutyRates(duty, pricing) {
  const base = Math.round(Number(duty.baseRate ?? duty.hospitalRate) || 0);
  const pct = Number(pricing.emergencyLocumHikePct);
  if (duty.type === "emergency" && Number.isFinite(pct) && pct > 0) {
    return { baseRate: base, hospitalRate: Math.round((base * (100 + pct)) / 100), emergencyHikePct: pct };
  }
  return { baseRate: base, hospitalRate: base };
}

exports.onDutyCreated = onDocumentCreated("duties/{dutyId}", async (event) => {
  const duty = event.data && event.data.data();
  if (!duty || !duty.agencyId) return;
  const pricing = (await db().collection("app_settings").doc("pricing").get()).data() || {};
  const rates = dutyRates(duty, pricing);
  // the rate the duty was created with: the fixed reference for later
  // checks (enforceDutySplit), never edited by the apps
  await db().collection("duty_quotes").doc(event.params.dutyId).set({
    hospitalRate: rates.hospitalRate,
    createdAt: new Date().toISOString(),
  }, { merge: true });
  const agency = (await db().collection("agencies").doc(duty.agencyId).get()).data() || {};
  const shares = splitDuty(rates.hospitalRate, agency);
  const fix = { ...rates, ...shares };
  if (Object.keys(fix).every((k) => fix[k] === duty[k])) return;
  await event.data.ref.update({ ...fix, payoutStatus: duty.payoutStatus || "due" });
});

exports.markAbsentDuties = onSchedule(
  { schedule: "every 15 minutes", timeZone: "Asia/Kolkata" },
  async () => {
    const now = Date.now();
    // today and yesterday (night shifts)
    const days = [istDateKey(now), istDateKey(now - 24 * 60 * 60 * 1000)];
    const snap = await db().collection("duties")
      .where("status", "==", "scheduled")
      .where("date", "in", days)
      .get();
    let marked = 0;
    for (const doc of snap.docs) {
      if (!isAbsentNow(doc.data(), now)) continue;
      await db().runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || !isAbsentNow(fresh.data(), now)) return;
        tx.update(doc.ref, {
          status: "absent",
          absentMarkedAt: new Date(now).toISOString(),
          autoAbsent: true,
        });
        marked++;
      });
    }
    if (marked) logger.info(`Marked ${marked} duties absent`);
  },
);

module.exports.splitDuty = splitDuty;
module.exports.dutyRates = dutyRates;
module.exports.isAbsentNow = isAbsentNow;
module.exports.istDateKey = istDateKey;
