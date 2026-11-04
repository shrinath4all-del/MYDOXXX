// Care physician agency server functions against an in-memory Firestore.
// Usage (in functions/): npm install, then npm test
const path = require('path');
const assert = require('assert');
const fnDir = path.join(__dirname, '..');

const store = { agencies: {}, duties: {}, duty_quotes: {}, app_settings: { pricing: { emergencyLocumHikePct: 20 } } };
const docRef = (c, id) => ({
  id,
  get: async () => ({ exists: !!store[c][id], data: () => store[c][id] && { ...store[c][id] } }),
  update: async (u) => { store[c][id] = { ...store[c][id], ...u }; },
  set: async (u, o) => { store[c][id] = { ...(o && o.merge ? store[c][id] : {}), ...u }; },
});
const fakeDb = {
  collection: (c) => ({
    doc: (id) => docRef(c, id),
    where: (f1, _o1, v1) => ({
      where: (f2, _o2, v2) => ({
        get: async () => ({
          docs: Object.entries(store[c])
            .filter(([, d]) => d[f1] === v1 && v2.includes(d[f2]))
            .map(([id, d]) => ({ id, ref: docRef(c, id), data: () => ({ ...d }) })),
        }),
      }),
    }),
  }),
  runTransaction: async (fn) => fn({ get: (r) => r.get(), update: (r, u) => r.update(u) }),
};
const admin = require(require.resolve('firebase-admin', { paths: [fnDir] }));
Object.defineProperty(admin, 'firestore', { value: () => fakeDb, configurable: true, writable: true });

const care = require(path.join(fnDir, 'care_agency.js'));
const ts = (ms) => ({ toMillis: () => ms });

(async () => {
  // shares (₹3,200 ICU locum -> 2,560 / 480 / 160)
  assert.deepStrictEqual(care.splitDuty(3200, { splitDoctorPct: 80, splitAgencyPct: 15 }),
    { doctorPay: 2560, agencyShare: 480, appShare: 160 });
  assert.deepStrictEqual(care.splitDuty(1000, {}), { doctorPay: 800, agencyShare: 150, appShare: 50 });

  // onDutyCreated writes the shares from the agency split
  store.agencies.ag1 = { splitDoctorPct: 70, splitAgencyPct: 20, splitAppPct: 10 };
  store.duties.d1 = { agencyId: 'ag1', hospitalRate: 1000, doctorPay: 800, agencyShare: 150, appShare: 50 };
  await care.onDutyCreated.run({
    params: { dutyId: 'd1' },
    data: { data: () => store.duties.d1, ref: docRef('duties', 'd1') },
  });
  assert.deepStrictEqual(
    [store.duties.d1.doctorPay, store.duties.d1.agencyShare, store.duties.d1.appShare, store.duties.d1.payoutStatus],
    [700, 200, 100, 'due']);

  // emergency locum: the hospital is billed 20% more (app_settings/pricing),
  // and a client that already added it is not charged twice
  store.duties.d2 = { agencyId: 'ag1', type: 'emergency', hospitalRate: 3000 };
  await care.onDutyCreated.run({
    params: { dutyId: 'd2' },
    data: { data: () => store.duties.d2, ref: docRef('duties', 'd2') },
  });
  assert.deepStrictEqual(
    [store.duties.d2.baseRate, store.duties.d2.hospitalRate, store.duties.d2.doctorPay, store.duty_quotes.d2.hospitalRate],
    [3000, 3600, 2520, 3600]);
  store.duties.d3 = { agencyId: 'ag1', type: 'emergency', baseRate: 3000, hospitalRate: 3600 };
  await care.onDutyCreated.run({
    params: { dutyId: 'd3' },
    data: { data: () => store.duties.d3, ref: docRef('duties', 'd3') },
  });
  assert.strictEqual(store.duties.d3.hospitalRate, 3600);
  // a normal locum is billed the agency's rate
  assert.deepStrictEqual(care.dutyRates({ type: 'locum', hospitalRate: 3000 }, { emergencyLocumHikePct: 20 }),
    { baseRate: 3000, hospitalRate: 3000 });

  // IST date key
  assert.strictEqual(care.istDateKey(Date.parse('2026-10-05T20:00:00Z')), '2026-10-06');

  // markAbsentDuties: 4 h after start with no check-in
  const now = Date.now();
  const today = care.istDateKey(now);
  store.duties = {
    old: { status: 'scheduled', date: today, shiftStart: ts(now - 5 * 3600e3) },
    recent: { status: 'scheduled', date: today, shiftStart: ts(now - 2 * 3600e3) },
    checkedIn: { status: 'scheduled', date: today, shiftStart: ts(now - 5 * 3600e3), checkInAt: ts(now - 4.5 * 3600e3) },
  };
  await care.markAbsentDuties.run({});
  assert.strictEqual(store.duties.old.status, 'absent');
  assert.strictEqual(store.duties.old.autoAbsent, true);
  assert.strictEqual(store.duties.recent.status, 'scheduled');
  assert.strictEqual(store.duties.checkedIn.status, 'scheduled');

  console.log('All care agency function tests passed');
})().catch((e) => { console.error('FAILED:', e.stack || e.message); process.exit(1); });
