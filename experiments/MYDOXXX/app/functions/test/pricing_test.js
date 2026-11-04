// Server prices (pricing.js) against an in-memory Firestore.
// Usage (in functions/): npm install, then npm test
const path = require('path');
const assert = require('assert');
const fnDir = path.join(__dirname, '..');

const store = {
  category_doctors: { 'General Physician': { name: 'General Physician', price: 520 }, 'Child Specialist': {} },
  lab_tests: { 'ECG Technician': { price: 600 } },
  therapies: { Physiotherapist: { price: 700 }, Old: { price: 900, isActive: false } },
  app_settings: { pricing: { urgentSurchargePct: 20, doctorHomeVisitExtra: 100, nurseDailyRate: 1000, sosEmergencyFee: 1200 } },
  agencies: { ag1: {} },
  duties: {},
  duty_quotes: {},
};
const col = (c) => (store[c] = store[c] || {});
const fakeDb = {
  collection: (c) => ({
    doc: (id) => ({
      get: async () => ({ exists: !!col(c)[id], data: () => col(c)[id] && { ...col(c)[id] } }),
      set: async (v, o) => { col(c)[id] = { ...(o && o.merge ? col(c)[id] : {}), ...v }; },
      create: async (v) => { if (col(c)[id]) throw new Error('exists'); col(c)[id] = { ...v }; },
    }),
    where: (f, _op, v) => ({ limit: () => ({ get: async () => {
      const docs = Object.values(col(c)).filter((d) => d[f] === v).map((d) => ({ data: () => ({ ...d }) }));
      return { empty: docs.length === 0, docs };
    } }) }),
  }),
};
const admin = require(require.resolve('firebase-admin', { paths: [fnDir] }));
Object.defineProperty(admin, 'firestore', { value: () => fakeDb, configurable: true, writable: true });
const { appointmentPrice, enforceDutySplit } = require(path.join(fnDir, 'pricing.js'));

(async () => {
  const price = async (a) => appointmentPrice(a);
  // the phone's price is ignored; Firestore decides
  assert.strictEqual((await price({ doctorCategory: 'General Physician', price: 1 })).price, 520);
  assert.strictEqual((await price({ doctorCategory: 'General Physician', consultationType: 'Home Visit' })).price, 620);
  assert.strictEqual((await price({ doctorCategory: 'General Physician', isUrgentEmergency: true })).price, 624);
  assert.ok((await price({ doctorCategory: 'Child Specialist' })).missing);
  assert.strictEqual((await price({ isNurseRequest: true, durationDays: 5, price: 10 })).price, 5000);
  assert.strictEqual((await price({ isTherapistRequest: true, therapyName: 'Physiotherapist', isUrgentEmergency: true })).price, 840);
  assert.ok((await price({ isTherapistRequest: true, therapyName: 'Old' })).missing, 'switched-off therapy');
  assert.strictEqual((await price({ isTechnicianRequest: true, testName: 'ECG Technician' })).price, 600);
  assert.strictEqual((await price({ consultationType: 'SOS Emergency Pipeline', price: 5 })).price, 1200);

  // editing a duty's rate is corrected once and then stops (no loop)
  store.duties.d1 = { agencyId: 'ag1', hospitalRate: 1000, doctorPay: 800, agencyShare: 150, appShare: 50 };
  const queue = [];
  const write = (next) => {
    const before = { ...store.duties.d1 };
    store.duties.d1 = { ...before, ...next };
    queue.push([before, { ...store.duties.d1 }]);
  };
  write({ hospitalRate: 500 });
  let writes = 0;
  while (queue.length && writes < 10) {
    const [b, a] = queue.shift();
    await enforceDutySplit.run({ params: { id: 'd1' }, data: {
      before: { exists: true, data: () => b },
      after: { exists: true, data: () => a, ref: { update: async (v) => { writes++; write(v); } } },
    } });
  }
  assert.strictEqual(writes, 1, 'one correction, then nothing');
  assert.strictEqual(store.duties.d1.hospitalRate, 1000);
  assert.strictEqual(store.duties.d1.doctorPay, 800);

  console.log('All pricing function tests passed');
})().catch((e) => { console.error('FAILED:', e); process.exit(1); });
