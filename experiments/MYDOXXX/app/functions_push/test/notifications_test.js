// Push notifications (notifications.js, care_physician.js) against an
// in-memory Firestore and a fake push sender: who is told, and what.
// Usage (in functions_push/): npm install, then npm test
const path = require('path');
const assert = require('assert');
const fnDir = path.join(__dirname, '..');

const store = {
  users: {},
  nurses: {
    n1: { preferredLocations: ['Wakad'] },
    n2: { preferredLocations: ['Aundh'] }, // other area
    n3: { preferredLocations: [] }, // any area
    n4: { preferredLocations: ['Wakad'], isOnline: false }, // offline
  },
  therapists: {
    t1: { preferredLocations: ['Wakad'] },
    t2: { preferredLocations: ['Wakad'] },
  },
  technicians: {},
  appointments: {},
  care_physicians: {
    cp1: { dutyTypes: ['home'], areas: ['Baner'], agencyId: 'ag1' },
  },
  shifts: {},
};
const col = (c) => (store[c] = store[c] || {});
// notification history: users/{uid}/notifications (saved by notify)
const history = [];
const ref = (c, id) => ({
  id,
  collection: (sub) => ({ doc: () => ({ owner: id, sub }) }),
  get: async () => ({ id, exists: !!col(c)[id], data: () => col(c)[id], ref: ref(c, id) }),
  update: async (u) => {
    for (const [k, v] of Object.entries(u)) {
      if (v && v.__union) col(c)[id][k] = [...new Set([...(col(c)[id][k] || []), ...v.__union])];
      else col(c)[id][k] = v;
    }
  },
});
const fakeDb = {
  collection: (c) => ({
    doc: (id) => ref(c, id),
    get: async () => {
      const docs = Object.entries(col(c)).map(([id, d]) => ({ id, data: () => d }));
      return { docs, forEach: (fn) => docs.forEach(fn) };
    },
    where: () => ({ get: async () => ({ docs: [], forEach: () => {} }) }),
  }),
  getAll: async (...refs) => Promise.all(refs.map((r) => r.get())),
  batch: () => {
    const writes = [];
    return {
      set: (r, data) => writes.push({ uid: r.owner, sub: r.sub, ...data }),
      commit: async () => history.push(...writes),
    };
  },
};
const admin = require(require.resolve('firebase-admin', { paths: [fnDir] }));
const sent = [];
Object.defineProperty(admin, 'firestore', {
  value: Object.assign(() => fakeDb, {
    FieldValue: { arrayUnion: (...v) => ({ __union: v }), arrayRemove: () => ({}), serverTimestamp: () => 'now' },
    Timestamp: { fromMillis: (ms) => ({ ms }) },
  }),
  configurable: true, writable: true,
});
Object.defineProperty(admin, 'messaging', {
  value: () => ({ sendEachForMulticast: async (m) => { sent.push(m); return { successCount: 1, failureCount: 0, responses: [{}] }; } }),
  configurable: true, writable: true,
});
admin.initializeApp = () => {};

const { notifyAppointment, notify } = require(path.join(fnDir, 'notifications.js'));
const { notifyCareShift } = require(path.join(fnDir, 'care_physician.js'));

// every user has a phone token named after them
const users = ['p1', 'n1', 'n2', 'n3', 'n4', 't1', 't2', 'cp1', 'ag1'];
for (const u of users) store.users[u] = { fcmTokens: [`tok_${u}`] };
const told = (title) => sent.filter((m) => m.notification.title === title).map((m) => m.tokens[0].slice(4)).sort();

const write = (c, id, before, after) => (c === 'shifts' ? notifyCareShift : notifyAppointment).run({
  params: { id },
  data: {
    before: { exists: !!before, data: () => before },
    after: { exists: !!after, data: () => after, ref: ref(c, id) },
  },
});

(async () => {
  // 1. a nurse declines: the request goes to every nurse in the area
  const base = { patientUid: 'p1', patientName: 'Ravi', roleTarget: 'nurse', isNurseRequest: true,
    locationName: 'Wakad, Pune', date: '14/10/2026', time: '07:00 PM', doctorUid: 'n9' };
  store.appointments.a1 = { ...base, status: 'Broadcasted', isBroadcast: true, declinedBy: ['n9'] };
  await write('appointments', 'a1', { ...base, status: 'Pending Home Visit' }, store.appointments.a1);
  assert.deepStrictEqual(told('New nursing request'), ['n1', 'n3'],
    'Wakad nurses and "any area" nurses; not Aundh, not offline');

  // 2. "any physio" during a physio agency's window: only the offered physios
  store.appointments.a2 = { patientUid: 'p1', roleTarget: 'therapist', isTherapistRequest: true,
    therapyName: 'Physiotherapist', locationName: 'Wakad', status: 'Broadcasted', isBroadcast: true,
    routingStage: 'team', agencyOfferedTo: ['t2'],
    agencyOfferExpiresAt: new Date(Date.now() + 10 * 60000).toISOString() };
  await write('appointments', 'a2', null, store.appointments.a2);
  assert.deepStrictEqual(told('New therapy request'), ['t2']);

  // 3. a nurse accepts: the patient is told by name, without "Dr."
  const accepted = { ...base, status: 'Confirmed', doctorName: 'Priya', paymentStatus: 'pending' };
  await write('appointments', 'a3', { ...base, status: 'Broadcasted' }, accepted);
  const acc = sent.find((m) => m.notification.title === 'Request accepted');
  assert.strictEqual(acc.notification.body,
    'Priya accepted your nursing visit request. Please pay in My Bookings to confirm.');
  await write('appointments', 'a3', accepted, { ...accepted, status: 'In Progress' });
  assert.ok(told('Nursing visit started').includes('p1'));

  // 4. a doctor's booking still says "Dr."
  const doc = { patientUid: 'p1', doctorName: 'Kunal', status: 'Confirmed' };
  await write('appointments', 'a4', { ...doc, status: 'Pending Home Visit' }, doc);
  assert.ok(sent.some((m) => m.notification.body === 'Dr. Kunal accepted your consultation request.'));

  // 5. care physician home visit: no "agency gets it first" wording
  const visit = { postedBy: 'patient', posterId: 'p1', status: 'open', dutyType: 'home', area: 'Baner, Pune',
    serviceName: 'IV Line Insertion', pay: 850, date: '2099-10-14', start: '08:00',
    offerAgencyIds: ['ag1'], agencyOfferUntil: new Date(Date.now() + 10 * 60000).toISOString() };
  store.shifts.s1 = { ...visit };
  await write('shifts', 's1', null, store.shifts.s1);
  const visitPushes = sent.filter((m) => m.notification.title.includes('home visit'));
  assert.deepStrictEqual(visitPushes.map((m) => m.tokens[0]), ['tok_cp1'],
    'the doctor is told; the agency is not (it does not see home visits)');
  for (const m of visitPushes) {
    assert.ok(!/first|15 min|for your agency/i.test(m.notification.title + m.notification.body),
      m.notification.title + ' / ' + m.notification.body);
  }

  // 6. offline providers get no request pushes
  const before6 = sent.length;
  store.appointments.a6 = { patientUid: 'p1', roleTarget: 'nurse', isNurseRequest: true,
    doctorUid: 'n4', status: 'Pending Home Visit', locationName: 'Wakad' };
  await write('appointments', 'a6', null, store.appointments.a6);
  assert.ok(!sent.slice(before6).some((m) => m.tokens[0] === 'tok_n4'), 'direct booking to an offline nurse');
  store.therapists.t2.isOnline = false;
  store.appointments.a7 = { ...store.appointments.a2, pushedUids: [] };
  const before7 = sent.length;
  await write('appointments', 'a7', null, store.appointments.a7);
  assert.strictEqual(sent.length, before7, 'agency physio went offline after the offer');

  // 7. every push is kept in the account's notification list (the bell),
  // chat messages are not (the Chat tab lists them)
  const saved = history.filter((h) => h.uid === 'p1' && h.title === 'Request accepted');
  assert.ok(saved.length > 0, 'accepted push saved for the patient');
  assert.strictEqual(saved[0].sub, 'notifications');
  assert.ok(saved[0].body.startsWith('Priya accepted'));
  assert.ok(history.some((h) => h.uid === 'cp1' && h.title.includes('home visit')),
    'care physician pushes are saved too');
  const noToken = 'nt1';
  store.users[noToken] = {};
  await notify([noToken], { title: 'Duty assigned', body: 'x', data: { type: 'care_shift' } });
  assert.ok(history.some((h) => h.uid === noToken), 'saved even with no phone to push to');
  const before7b = history.length;
  await notify(['p1'], { title: 'Ravi', body: 'hi', data: { type: 'chat', chatId: 'p1_n1' } });
  assert.strictEqual(history.length, before7b, 'chat messages are not saved');

  console.log('All notification tests passed');
})().catch((e) => { console.error('FAILED:', e); process.exit(1); });
