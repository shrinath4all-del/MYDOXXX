/**
 * Prices are decided here, from Firestore, never by the phone.
 *
 *   Masters (edited in the Firebase console):
 *     category_doctors/{name}.price         doctor consultation
 *     lab_tests/{name}.price                technician test
 *     therapies/{name}.price                therapy session
 *     care_physician_services/{id}.price    care physician home visit
 *     app_settings/pricing                  urgentSurchargePct (20),
 *                                           doctorHomeVisitExtra (100),
 *                                           nurseDailyRate (1000),
 *                                           sosEmergencyFee (1200),
 *                                           emergencyLocumHikePct (20,
 *                                           applied by onDutyCreated)
 *
 *   enforceAppointmentPrice  any booking write: when the booking's price or
 *                            what it depends on changed, the price is worked
 *                            out again and corrected (until it is paid)
 *   enforceVisitFee          a patient's care physician home visit always
 *                            costs its service's price
 *   enforceDutySplit         the doctor / agency / app shares of a duty are
 *                            recomputed if anyone edits them, always from the
 *                            rate saved once in duty_quotes/{id} (so the
 *                            correction itself never triggers another one)
 *   appointmentPrice()       used by createRazorpayOrder, so the amount
 *                            charged is always the server's
 *
 * If a price is missing in Firestore the booking gets priceStatus
 * 'missing' and cannot be paid online until it is set.
 */
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { splitDuty } = require("./care_agency");

const db = () => admin.firestore();
const SOS = "SOS Emergency Pipeline";

// fields that decide the price; a change to any of them is re-checked
const APPOINTMENT_INPUTS = [
  "price", "basePrice", "offeredExtraAmount", "urgentSurcharge", "emergencySurcharge",
  "consultationType", "isUrgentEmergency", "doctorCategory", "therapyName",
  "testName", "durationDays", "isNurseRequest", "isTherapistRequest",
  "isTechnicianRequest", "roleTarget",
];

const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : Number(v));
const positive = (v) => Number.isFinite(num(v)) && num(v) > 0;

async function settings() {
  const snap = await db().collection("app_settings").doc("pricing").get();
  return snap.exists ? snap.data() : {};
}

/** price of a master item by doc id or by its 'name' field (null if unset). */
async function masterPrice(collection, name) {
  const key = String(name || "").trim();
  if (!key) return null;
  let data = null;
  try {
    const doc = await db().collection(collection).doc(key).get();
    if (doc.exists) data = doc.data();
  } catch (_) {
    // ids with '/' are not valid doc ids: fall through to the name lookup
  }
  if (!data) {
    const q = await db().collection(collection).where("name", "==", key).limit(1).get();
    if (!q.empty) data = q.docs[0].data();
  }
  if (!data || data.isActive === false || !positive(data.price)) return null;
  return Math.round(num(data.price));
}

const kind = (a) => {
  if (a.consultationType === SOS) return "sos";
  if (a.isNurseRequest || a.roleTarget === "nurse") return "nurse";
  if (a.isTherapistRequest || a.roleTarget === "therapist") return "therapist";
  if (a.isTechnicianRequest || a.roleTarget === "technician") return "technician";
  return "doctor";
};

/**
 * The booking's price fields as the server works them out, or
 * { missing: '<what is not set>' }.
 */
async function appointmentPrice(a, s) {
  s = s || (await settings());
  const pct = num(s.urgentSurchargePct);
  const urgentExtra = (base) => (a.isUrgentEmergency === true && Number.isFinite(pct)
    ? Math.round((base * pct) / 100) : 0);
  const needPct = a.isUrgentEmergency === true && !Number.isFinite(pct);

  switch (kind(a)) {
    case "sos": {
      if (!positive(s.sosEmergencyFee)) return { missing: "app_settings/pricing.sosEmergencyFee" };
      const fee = Math.round(num(s.sosEmergencyFee));
      return { basePrice: fee, offeredExtraAmount: 0, price: fee };
    }
    case "nurse": {
      if (!positive(s.nurseDailyRate)) return { missing: "app_settings/pricing.nurseDailyRate" };
      const rate = Math.round(num(s.nurseDailyRate));
      const days = Math.max(1, Math.round(num(a.durationDays) || 1));
      return { dailyRate: rate, basePrice: rate * days, offeredExtraAmount: 0, price: rate * days };
    }
    case "therapist": {
      const base = await masterPrice("therapies", a.therapyName);
      if (base == null) return { missing: `therapies/${a.therapyName}.price` };
      if (needPct) return { missing: "app_settings/pricing.urgentSurchargePct" };
      const extra = urgentExtra(base);
      return {
        basePrice: base, urgentSurcharge: extra, emergencySurcharge: extra,
        offeredExtraAmount: 0, price: base + extra,
      };
    }
    case "technician": {
      const base = await masterPrice("lab_tests", a.testName);
      if (base == null) return { missing: `lab_tests/${a.testName}.price` };
      return { basePrice: base, offeredExtraAmount: 0, price: base };
    }
    default: {
      const base = await masterPrice("category_doctors", a.doctorCategory);
      if (base == null) return { missing: `category_doctors/${a.doctorCategory}.price` };
      if (needPct) return { missing: "app_settings/pricing.urgentSurchargePct" };
      let extra = urgentExtra(base);
      if (a.isUrgentEmergency !== true && a.consultationType === "Home Visit") {
        if (!Number.isFinite(num(s.doctorHomeVisitExtra))) {
          return { missing: "app_settings/pricing.doctorHomeVisitExtra" };
        }
        extra = Math.round(num(s.doctorHomeVisitExtra));
      }
      const out = { basePrice: base, offeredExtraAmount: extra, price: base + extra };
      if (a.emergencySurcharge != null) out.emergencySurcharge = a.isUrgentEmergency === true ? extra : 0;
      return out;
    }
  }
}

const sameFields = (x, y, keys) => keys.every((k) => JSON.stringify(x[k]) === JSON.stringify(y[k]));

exports.appointmentPrice = appointmentPrice;

exports.enforceAppointmentPrice = onDocumentWritten("appointments/{id}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const a = event.data.after.exists ? event.data.after.data() : null;
  if (!a || a.paymentStatus === "paid") return;
  if (before && a.priceCheckedAt && sameFields(before, a, APPOINTMENT_INPUTS)) return;

  const p = await appointmentPrice(a);
  const ref = event.data.after.ref;
  if (p.missing) {
    logger.warn("price not set", { id: event.params.id, missing: p.missing });
    if (a.priceStatus !== "missing" || a.priceMissing !== p.missing) {
      await ref.update({ priceStatus: "missing", priceMissing: p.missing, priceCheckedAt: new Date().toISOString() });
    }
    return;
  }
  const wrong = Object.keys(p).filter((k) => num(a[k]) !== p[k]);
  if (wrong.length) {
    logger.warn("booking price corrected", {
      id: event.params.id, sent: Object.fromEntries(wrong.map((k) => [k, a[k]])), server: p,
    });
  }
  if (wrong.length || a.priceStatus !== "ok" || !a.priceCheckedAt) {
    await ref.update({
      ...p,
      priceStatus: "ok",
      priceMissing: admin.firestore.FieldValue.delete(),
      priceCheckedAt: new Date().toISOString(),
    });
  }
});

exports.enforceVisitFee = onDocumentWritten("shifts/{id}", async (event) => {
  const s = event.data.after.exists ? event.data.after.data() : null;
  if (!s || s.postedBy !== "patient") return;
  const before = event.data.before.exists ? event.data.before.data() : null;
  if (before && sameFields(before, s, ["pay", "serviceId"]) && s.feeCheckedAt) return;

  let fee = null;
  if (s.serviceId) {
    const doc = await db().collection("care_physician_services").doc(String(s.serviceId)).get();
    if (doc.exists && doc.data().isActive !== false && positive(doc.data().price)) {
      fee = Math.round(num(doc.data().price));
    }
  }
  if (fee == null) {
    logger.warn("visit fee not set", { id: event.params.id, serviceId: s.serviceId });
    if (s.feeStatus !== "missing") await event.data.after.ref.update({ feeStatus: "missing" });
    return;
  }
  if (num(s.pay) !== fee || !s.feeCheckedAt) {
    if (num(s.pay) !== fee) logger.warn("visit fee corrected", { id: event.params.id, sent: s.pay, server: fee });
    await event.data.after.ref.update({ pay: fee, feeStatus: "ok", feeCheckedAt: new Date().toISOString() });
  }
});

/**
 * The duty's fixed rate from duty_quotes/{id}. A duty from before quotes
 * existed gets one now, from the rate it had before this first edit; after
 * that the quote never changes, so repeated or late events all agree.
 */
async function quotedRate(id, before) {
  const ref = db().collection("duty_quotes").doc(id);
  const snap = await ref.get();
  if (snap.exists) return Math.round(num(snap.data().hospitalRate) || 0);
  const rate = Math.round(num(before.hospitalRate) || 0);
  try {
    await ref.create({ hospitalRate: rate, createdAt: new Date().toISOString(), fromEdit: true });
    return rate;
  } catch (_) {
    // created at the same moment by another event: use that one
    return Math.round(num((await ref.get()).data().hospitalRate) || 0);
  }
}

exports.enforceDutySplit = onDocumentWritten("duties/{id}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const d = event.data.after.exists ? event.data.after.data() : null;
  // new duties are split by onDutyCreated; this only guards later edits
  if (!before || !d || !d.agencyId) return;
  const keys = ["hospitalRate", "doctorPay", "agencyShare", "appShare"];
  if (sameFields(before, d, keys)) return;
  const rate = await quotedRate(event.params.id, before);
  const agency = (await db().collection("agencies").doc(d.agencyId).get()).data() || {};
  const fixed = { hospitalRate: rate, ...splitDuty(rate, agency) };
  if (keys.every((k) => num(d[k]) === fixed[k])) return;
  logger.warn("duty money corrected", { id: event.params.id });
  await event.data.after.ref.update(fixed);
});
