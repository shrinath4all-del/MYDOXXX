// Runs functions/razorpay.js and razorpay_route.js against an in-memory
// Firestore and a fake Razorpay API.
// Usage (in functions/): npm install, then npm test
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const fnDir = path.join(__dirname, '..');

process.env.RAZORPAY_KEY_ID = 'rzp_test_key';
process.env.RAZORPAY_KEY_SECRET = 'test_secret';
process.env.RAZORPAY_WEBHOOK_SECRET = 'hook_secret';

// ---- in-memory Firestore: store[collection][id]
const store = {};
const col = (c) => (store[c] = store[c] || {});
const docRef = (c, id) => ({
  id,
  get: async () => ({ exists: !!col(c)[id], data: () => col(c)[id] && { ...col(c)[id] } }),
  update: async (u) => { col(c)[id] = { ...col(c)[id], ...u }; },
  set: async (u, opts) => { col(c)[id] = opts && opts.merge ? { ...col(c)[id], ...u } : { ...u }; },
});
const fakeDb = {
  collection: (c) => ({
    doc: (id) => docRef(c, id),
    where: (field, _op, value) => ({
      limit: () => ({
        get: async () => {
          const docs = Object.entries(col(c))
            .filter(([, d]) => d[field] === value)
            .map(([id]) => ({ id, ref: docRef(c, id) }));
          return { empty: docs.length === 0, docs };
        },
      }),
    }),
  }),
  runTransaction: async (fn) => fn({
    get: (ref) => ref.get(),
    update: (ref, u) => ref.update(u),
  }),
};
const admin = require(require.resolve('firebase-admin', { paths: [fnDir] }));
Object.defineProperty(admin, 'firestore', { value: () => fakeDb, configurable: true, writable: true });

// ---- fake Razorpay API
const calls = [];
let orders = 0;
global.fetch = async (url, opts) => {
  const auth = Buffer.from('rzp_test_key:test_secret').toString('base64');
  assert.strictEqual(opts.headers.Authorization, `Basic ${auth}`);
  const p = url.replace('https://api.razorpay.com', '');
  const body = opts.body ? JSON.parse(opts.body) : undefined;
  calls.push({ method: opts.method, path: p, body });
  const ok = (json) => ({ ok: true, status: 200, json: async () => json });
  if (p === '/v1/orders') return ok({ id: `order_${++orders}`, amount: body.amount });
  if (p === '/v2/accounts') return ok({ id: 'acc_1' });
  if (p === '/v2/accounts/acc_1/stakeholders') return ok({ id: 'sth_1' });
  if (p === '/v2/accounts/acc_1/products') return ok({ id: 'acc_prd_1', activation_status: 'requested' });
  if (p === '/v2/accounts/acc_1/products/acc_prd_1') {
    return ok({ id: 'acc_prd_1', activation_status: 'under_review', requirements: [] });
  }
  if (p === '/v1/payments/pay_1/transfers') return ok({ items: [{ id: 'trf_1', recipient: 'acc_1' }] });
  if (p === '/v1/transfers/trf_1') return ok({ id: 'trf_1', on_hold: false });
  if (p === '/v1/payments/pay_2/refund') return ok({ id: 'rfnd_1' });
  throw new Error('unexpected Razorpay call ' + opts.method + ' ' + p);
};

const rzp = require(path.join(fnDir, 'razorpay.js'));
const route = require(path.join(fnDir, 'razorpay_route.js'));
const call = (fn, uid, data) => fn.run({ auth: uid ? { uid } : undefined, data });
const expectError = async (p, code, text) => {
  try { await p; assert.fail('expected ' + code); } catch (e) {
    assert.strictEqual(e.code, code, e.message);
    if (text) assert.ok(e.message.includes(text), e.message);
  }
};
const settle = (id, before, after) => route.settleBookingPayment.run({
  params: { id },
  data: {
    before: { data: () => before },
    after: { data: () => after, ref: docRef('appointments', id) },
  },
});

const bankDetails = {
  legalName: 'Asha Patil', email: 'asha@example.com', phone: '+91 98765 43210',
  pan: 'ABCPA1234Z', accountNumber: '123456789012', ifsc: 'HDFC0001234',
  street: '12 FC Road, Shivajinagar', city: 'Pune', state: 'MH', postalCode: '411005',
};

(async () => {
  // ---------------- provider payout setup
  col('users').phy1 = { role: 'therapist' };
  col('users').pat1 = { role: 'patient' };
  col('therapists').phy1 = { name: 'Asha' };

  await expectError(call(route.setupProviderPayouts, 'pat1', bankDetails), 'permission-denied');
  await expectError(call(route.setupProviderPayouts, 'phy1', { ...bankDetails, pan: 'ABCDE1234F', ifsc: 'X' }),
    'invalid-argument', 'IFSC');

  const setup = await call(route.setupProviderPayouts, 'phy1', bankDetails);
  assert.strictEqual(setup.status, 'under_review');
  const acc = calls.find((c) => c.path === '/v2/accounts').body;
  assert.strictEqual(acc.business_type, 'individual');
  assert.strictEqual(acc.profile.subcategory, 'health_practitioners_medical_services');
  assert.strictEqual(acc.profile.addresses.registered.postal_code, 411005);
  assert.strictEqual(acc.phone, '9876543210');
  const bank = calls.find((c) => c.method === 'PATCH' && c.path.endsWith('acc_prd_1')).body;
  assert.deepStrictEqual(bank.settlements,
    { account_number: '123456789012', ifsc_code: 'HDFC0001234', beneficiary_name: 'Asha Patil' });
  // only masked bank details stored
  const phy = col('therapists').phy1;
  assert.strictEqual(phy.payoutAccountId, 'acc_1');
  assert.strictEqual(phy.payoutBankLast4, '9012');
  assert.ok(!JSON.stringify(phy).includes('123456789012'));

  // ---------------- payment before payouts are active is refused
  // the amount comes from the therapy's price in Firestore (pricing.js)
  col('therapies').Physiotherapist = { name: 'Physiotherapist', price: 800 };
  col('appointments').a1 = { patientUid: 'pat1', status: 'Confirmed', price: 800, paymentStatus: 'pending',
    isTherapistRequest: true, therapyName: 'Physiotherapist',
    doctorUid: 'phy1', doctorName: 'Asha', patientName: 'Ravi' };
  await expectError(call(rzp.createRazorpayOrder, 'pat1', { appointmentId: 'a1' }),
    'failed-precondition', 'setting up payouts');

  // activation arrives by webhook
  const actEvent = { event: 'product.route.activated', account_id: 'acc_1',
    payload: { merchant_product: { entity: { activation_status: 'activated' } } } };
  const actRaw = Buffer.from(JSON.stringify(actEvent));
  const resp = () => { const r = { code: 0, status(c) { r.code = c; return r; }, send() { return r; } }; return r; };
  const act = resp();
  await rzp.razorpayWebhook({ method: 'POST', rawBody: actRaw, body: actEvent,
    get: () => crypto.createHmac('sha256', 'hook_secret').update(actRaw).digest('hex') }, act);
  assert.strictEqual(act.code, 200);
  assert.strictEqual(col('therapists').phy1.payoutStatus, 'activated');

  // ---------------- order is split 10% / 90%, provider part on hold
  await expectError(call(rzp.createRazorpayOrder, null, { appointmentId: 'a1' }), 'unauthenticated');
  await expectError(call(rzp.createRazorpayOrder, 'other', { appointmentId: 'a1' }), 'permission-denied');
  const o = await call(rzp.createRazorpayOrder, 'pat1', { appointmentId: 'a1' });
  assert.deepStrictEqual([o.orderId, o.amount, o.description], ['order_1', 80000, 'Physiotherapy session']);
  const orderBody = calls.find((c) => c.path === '/v1/orders').body;
  assert.deepStrictEqual(orderBody.transfers.map((t) => [t.account, t.amount, t.on_hold]),
    [['acc_1', 72000, true]]);
  assert.strictEqual(col('appointments').a1.platformFee, 80);
  assert.strictEqual(col('appointments').a1.providerShare, 720);
  // retry reuses the order
  assert.strictEqual((await call(rzp.createRazorpayOrder, 'pat1', { appointmentId: 'a1' })).orderId, 'order_1');
  assert.strictEqual(orders, 1);

  // ---------------- payment verification
  await expectError(call(rzp.verifyRazorpayPayment, 'pat1',
    { appointmentId: 'a1', orderId: 'order_1', paymentId: 'pay_1', signature: 'bad' }), 'permission-denied');
  const sig = crypto.createHmac('sha256', 'test_secret').update('order_1|pay_1').digest('hex');
  await call(rzp.verifyRazorpayPayment, 'pat1',
    { appointmentId: 'a1', orderId: 'order_1', paymentId: 'pay_1', signature: sig });
  assert.strictEqual(col('appointments').a1.paymentStatus, 'paid');
  assert.strictEqual(col('appointments').a1.amountPaid, 800);

  // ---------------- visit completed: provider's 90% released
  const paid = col('appointments').a1;
  await settle('a1', { ...paid, status: 'In Progress' }, { ...paid, status: 'Completed' });
  assert.ok(calls.some((c) => c.method === 'PATCH' && c.path === '/v1/transfers/trf_1' && c.body.on_hold === false));
  assert.strictEqual(col('appointments').a1.payoutReleased, true);

  // ---------------- provider absent after payment: full refund, transfer reversed
  col('appointments').a2 = { patientUid: 'pat1', status: 'Provider Absent', paymentStatus: 'paid',
    razorpayPaymentId: 'pay_2', razorpayOrderAmount: 50000, payoutAccountId: 'acc_1' };
  await settle('a2', { ...col('appointments').a2, status: 'Confirmed' }, col('appointments').a2);
  const refund = calls.find((c) => c.path === '/v1/payments/pay_2/refund').body;
  assert.deepStrictEqual([refund.amount, refund.reverse_all], [50000, 1]);
  assert.strictEqual(col('appointments').a2.paymentStatus, 'refunded');

  // ---------------- payment webhook (backup to verify)
  col('appointments').a3 = { patientUid: 'pat2', status: 'Confirmed', price: 300,
    paymentStatus: 'pending', razorpayOrderId: 'order_9' };
  const event = { event: 'payment.captured', payload: { payment: { entity: {
    id: 'pay_9', order_id: 'order_9', amount: 30000, notes: { appointmentId: 'a3' } } } } };
  const raw = Buffer.from(JSON.stringify(event));
  const bad = resp();
  await rzp.razorpayWebhook({ method: 'POST', rawBody: raw, body: event, get: () => 'nope' }, bad);
  assert.strictEqual(bad.code, 400);
  assert.strictEqual(col('appointments').a3.paymentStatus, 'pending');
  const good = resp();
  await rzp.razorpayWebhook({ method: 'POST', rawBody: raw, body: event,
    get: () => crypto.createHmac('sha256', 'hook_secret').update(raw).digest('hex') }, good);
  assert.strictEqual(col('appointments').a3.paymentStatus, 'paid');

  // ---------------- split rounding
  assert.deepStrictEqual(route.splitAmount(99900), { platform: 9990, provider: 89910 });
  assert.deepStrictEqual(route.splitAmount(12345), { platform: 1235, provider: 11110 });

  console.log('All Razorpay function tests passed');
})().catch((e) => { console.error('FAILED:', e.stack || e.message); process.exit(1); });
