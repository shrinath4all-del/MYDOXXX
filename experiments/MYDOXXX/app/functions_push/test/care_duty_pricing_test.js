'use strict';
const assert = require('node:assert/strict');
const { dutyPriceFields, masterDocumentId, enforceDutyRate } = require('../care_duty_pricing');

const master = { hospitalRate: 2000, monthlySalary: 55000 };
const expectedRates = {
  small: { icu: 1500, ward: 1100, casualty: 1200, specialty: 1500 },
  medium: { icu: 2000, ward: 1500, casualty: 1800, specialty: 2000 },
  high: { icu: 2500, ward: 1700, casualty: 2000, specialty: 2500 },
};
for (const [category, duties] of Object.entries(expectedRates)) {
  for (const [dutyType, pay] of Object.entries(duties)) {
    const got = dutyPriceFields({ dutyType, category, master });
    assert.equal(got.pay, pay, `${category}/${dutyType}`);
    assert.equal(got.doctorPay + got.saiShare + got.mydoxShare, pay);
  }
}
assert.equal(masterDocumentId('specialty'), 'icu');
assert.equal(masterDocumentId('casualty'), 'specialty');
assert.equal(masterDocumentId('ward'), 'ward');
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'unknown', master }).pay, 2000);
assert.equal(dutyPriceFields({ dutyType: 'icu', category: ' HIGH ', master }).pay, 2500);
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', master: null }).pay, 1500);
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', master: { ...master, active: false } }), null);
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', master: { hospitalRate: 0 } }), null);
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', master: null, monthly: true }), null);
const overridden = dutyPriceFields({ dutyType: 'icu', category: 'small',
  master: { ...master, categoryRates: { small: 1600 } } });
assert.deepEqual(overridden, { pay: 1600, doctorPay: 1360, marginAmount: 240,
  saiShare: 180, mydoxShare: 60, rateSource: 'master' });
for (const override of [0, 0.4, -1, '1600', Infinity, NaN, null]) {
  assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small',
    master: { ...master, categoryRates: { small: override } } }).pay, 1500);
}
const monthly = dutyPriceFields({ dutyType: 'icu', category: 'small', monthly: true,
  master: { ...master, categoryRates: { small: 1600 } } });
assert.equal(monthly.pay, 55000);
assert.equal(monthly.doctorPay, 46750);
assert.equal(monthly.payPeriod, 'month');
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', monthly: true,
  master: { ...master, monthlySalary: 0.4 } }), null,
  'a positive amount rounding to zero must not overwrite a shift with zero pay');
assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small',
  master: { ...master, categoryRates: { small: 0.4 } } }).pay, 1500);

for (const invalid of [
  { hospitalRate: 0.4 },
  { hospitalRate: Infinity },
  { ...master, platformMarginPct: 101 },
  { ...master, saiSharePct: 0, mydoxSharePct: 0 },
]) {
  assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', master: invalid }), null);
}
for (const monthlySalary of [0.4, Infinity, NaN, -1, '55000']) {
  assert.equal(dutyPriceFields({ dutyType: 'icu', category: 'small', monthly: true,
    master: { ...master, monthlySalary } }), null);
}

// Exercise the authoritative read/update boundary against an injected database.
// No Firebase SDK, credentials, network or emulator is used.
(async () => {
  const rows = {
    care_duty_rates: {
      icu: { ...master, categoryRates: { small: 1600 } },
      specialty: { hospitalRate: 1800, monthlySalary: 49000,
        categoryRates: { small: 1300 } },
    },
    hospitals: { h1: { rateCategory: 'small' } },
  };
  const reads = [];
  const writes = [];
  const db = { collection: (collection) => ({ doc: (id) => ({ get: async () => {
    reads.push(`${collection}/${id}`);
    const value = rows[collection]?.[id];
    return { exists: value != null, data: () => value };
  } }) }) };
  const ref = { update: async (patch) => writes.push(patch) };
  const draft = { postedBy: 'hospital', posterId: 'h1', dutyType: 'specialty', pay: 9999 };
  const fixed = await enforceDutyRate(db, ref, draft);
  assert.equal(fixed.pay, 1600, 'specialty uses ICU category override, not old specialty global price');
  assert.deepEqual(reads.sort(), ['care_duty_rates/icu', 'hospitals/h1']);
  assert.equal(writes.length, 1);
  await enforceDutyRate(db, ref, fixed);
  assert.equal(writes.length, 1, 'already-correct trigger data does not cause a write loop');
  const casualty = await enforceDutyRate(db, ref, { ...draft, dutyType: 'casualty' });
  assert.equal(casualty.pay, 1300, 'casualty uses old specialty master document');
  const team = await enforceDutyRate(db, ref, { ...draft, payPeriod: 'month' });
  assert.equal(team.pay, 55000, 'specialty monthly salary uses ICU master; category does not scale salary');
  const count = reads.length;
  const patient = { ...draft, postedBy: 'patient' };
  assert.equal(await enforceDutyRate(db, ref, patient), patient);
  assert.equal(reads.length, count, 'patient/agency prices are untouched');
  process.stdout.write('Care duty pricing: category matrix, overrides, mappings, monthly and trigger boundary passed.\n');
})().catch((error) => { console.error(error); process.exitCode = 1; });
