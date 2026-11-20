"use strict";

// Mirrors CareDutyRates: monthly salaries stay independent of hospital size.
const CATEGORY_RATES = Object.freeze({
  small: { icu: 1500, ward: 1100, casualty: 1200, specialty: 1500 },
  medium: { icu: 2000, ward: 1500, casualty: 1800, specialty: 2000 },
  high: { icu: 2500, ward: 1700, casualty: 2000, specialty: 2500 },
});
const SOURCE_DOC = Object.freeze({ specialty: "icu", casualty: "specialty" });
const positive = (v) => typeof v === "number" && Number.isFinite(v) && v > 0 && Math.round(v) > 0;
const percentage = (v, fallback) =>
  typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : fallback;

function normalizeCategory(value) {
  const c = String(value || "").trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(CATEGORY_RATES, c) ? c : "medium";
}

function masterDocumentId(dutyType) {
  return Object.prototype.hasOwnProperty.call(SOURCE_DOC, dutyType) ? SOURCE_DOC[dutyType] : dutyType;
}

/** Pure pricing policy shared by the trigger and its offline regression tests. */
function dutyPriceFields({ dutyType, category, master, monthly = false }) {
  const c = normalizeCategory(category);
  if (master != null && (master.active === false || !positive(master.hospitalRate))) return null;
  const base = master || {};
  const override = base.categoryRates && base.categoryRates[c];
  const standard = Object.prototype.hasOwnProperty.call(CATEGORY_RATES[c], dutyType)
    ? CATEGORY_RATES[c][dutyType] : null;
  const raw = monthly
    ? base.monthlySalary
    : positive(override) ? override : standard || base.hospitalRate;
  if (!positive(raw)) return null;
  const pay = Math.round(raw);
  if (pay <= 0) return null;
  const pct = percentage(base.platformMarginPct, 15);
  const sai = percentage(base.saiSharePct, 75);
  const mydox = percentage(base.mydoxSharePct, 25);
  if (pct > 100 || sai + mydox <= 0) return null;
  const margin = Math.round(pay * pct / 100);
  const saiShare = Math.round(margin * sai / (sai + mydox));
  return {
    pay,
    doctorPay: pay - margin,
    marginAmount: margin,
    saiShare,
    mydoxShare: margin - saiShare,
    rateSource: "master",
    ...(monthly ? { payPeriod: "month" } : {}),
  };
}

/** Injected Firestore keeps this module independently testable without an SDK. */
async function enforceDutyRate(db, ref, shift) {
  if (shift.postedBy !== "hospital" || !shift.dutyType) return shift;
  const masterId = masterDocumentId(String(shift.dutyType));
  const [masterSnap, hospitalSnap] = await Promise.all([
    db.collection("care_duty_rates").doc(masterId).get(),
    shift.posterId
      ? db.collection("hospitals").doc(String(shift.posterId)).get()
      : Promise.resolve(null),
  ]);
  const fixed = dutyPriceFields({
    dutyType: String(shift.dutyType),
    category: hospitalSnap && hospitalSnap.exists ? hospitalSnap.data().rateCategory : null,
    master: masterSnap.exists ? masterSnap.data() : null,
    monthly: shift.payPeriod === "month",
  });
  if (!fixed || Object.keys(fixed).every((key) => shift[key] === fixed[key])) return shift;
  await ref.update(fixed);
  return { ...shift, ...fixed };
}

module.exports = { normalizeCategory, masterDocumentId, dutyPriceFields, enforceDutyRate };
