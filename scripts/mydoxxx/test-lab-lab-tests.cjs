// Owner-requested lab-test catalogue for the synthetic test room: the 21 tests
// of the IT team's 21 Nov delivery, in the groups the app shows (Neuro / Blood /
// Other). Writes ONLY lab_tests/* in the named synthetic database. No Auth,
// rules, profiles, bookings or default-database writes; nothing is deleted;
// a price already set is never changed.
//
//   node scripts/mydoxxx/test-lab-lab-tests.cjs review [--price=500]   reads only, saves a private receipt
//   node scripts/mydoxxx/test-lab-lab-tests.cjs apply                   writes exactly the reviewed plan
//   node scripts/mydoxxx/test-lab-lab-tests.cjs verify                  reads back and checks
//
// Needs the owner's Firebase CLI login on the owner's PC (like the other
// test-lab helpers). Run only with the owner's explicit approval.
const C = require('./common.cjs');
const P = require('./test-lab-plan.cjs');
const L = require('./test-lab.cjs');
const RECEIPT = 'test-lab-lab-tests-review.json';
const DONE = 'test-lab-lab-tests-verification.json';
const COLLECTION = 'lab_tests';
const MIGRATION = 'lab-tests-v1';

// name -> [group, position in the group, minutes]  (firestore_seed/set_lab_tests.js, 21 Nov)
const TESTS = Object.freeze({
  'EEG': ['neuro', 1, 90], 'NCS': ['neuro', 2, 60], 'EMG': ['neuro', 3, 60], 'VEP': ['neuro', 4, 45],
  'BERA': ['neuro', 5, 45], 'Audiometry': ['neuro', 6, 45], 'RNS': ['neuro', 7, 45], 'Blink test': ['neuro', 8, 30],
  'CBC (Complete Blood Count)': ['blood', 1, 30], 'LFT (Liver Function Test)': ['blood', 2, 30],
  'TFT (Thyroid Function Test)': ['blood', 3, 30], 'RFT (Renal Function Test)': ['blood', 4, 30],
  'HbA1c': ['blood', 5, 30], 'FBS (Fasting Blood Sugar)': ['blood', 6, 30], 'PPBS (Post-Prandial Blood Sugar)': ['blood', 7, 30],
  'ECG': ['other', 1, 30], 'X-Ray': ['other', 2, 45], 'VNG': ['other', 3, 45], 'Allergy test': ['other', 4, 30],
  'Lab - Blood Draw': ['other', 5, null], 'OT Technician': ['other', 6, null],
});
// A test the room already has under a shorter name keeps that name (the
// synthetic technicians and old bookings use it) and only gets its group.
const SAME_AS = Object.freeze({'CBC (Complete Blood Count)': 'CBC'});

const slug = name => name.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
const norm = text => String(text ?? '').trim().toLowerCase();

function decode(v) {
  if ('nullValue' in v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, decode(x)]));
  throw Error('Unexpected field type');
}

function parsePrice(argv) {
  const arg = argv.find(a => a.startsWith('--price='));
  if (!arg) return null;
  const n = Number(arg.slice('--price='.length));
  C.assert(Number.isInteger(n) && n > 0 && n <= 100000, 'Use a whole-rupee --price between 1 and 100000');
  return n;
}

/** The changes for the tests already there ([existing]: {id, data, updateTime}) and the ones to add. Pure. */
function plan(existing, {price = null} = {}) {
  C.assert(price === null || (Number.isInteger(price) && price > 0), 'Invalid default price');
  const taken = new Set(existing.map(d => d.id));
  const out = [];
  for (const [name, [category, order, minutes]] of Object.entries(TESTS)) {
    const wanted = [norm(name), norm(SAME_AS[name])].filter(Boolean);
    const matches = existing.filter(d => wanted.includes(norm(d.data.name ?? d.id)) || wanted.map(slug).includes(d.id));
    C.assert(matches.length <= 1, 'Two existing tests match "' + name + '"; resolve by hand first');
    const found = matches[0];
    if (found) {
      const patch = {};
      if (found.data.category !== category) patch.category = category;
      if (found.data.order !== order) patch.order = order;
      if (found.data.time == null && minutes != null) patch.time = minutes;
      if (found.data.price == null && price != null) patch.price = price;
      if (Object.keys(patch).length) out.push({path: COLLECTION + '/' + found.id, name: found.data.name ?? found.id, exists: true, updateTime: found.updateTime, patch});
      continue;
    }
    const id = slug(name);
    C.assert(id && !taken.has(id), 'Document id already used: ' + id);
    taken.add(id);
    out.push({path: COLLECTION + '/' + id, name, exists: false, patch: {
      name, category, order, isActive: true, ...(minutes != null ? {time: minutes} : {}), ...(price != null ? {price} : {}),
      mydoxSynthetic: true, labMigration: MIGRATION}});
  }
  for (const item of out) C.assert(/^lab_tests\/[a-z0-9_]+$/i.test(item.path), 'Only lab_tests documents may be written');
  return out;
}

async function context() {
  const ctx = await L.adminContext();
  const db = (await ctx.firestore.get('/' + P.BASE)).body;
  C.assert.equal(db.name, P.BASE); C.assert.equal(db.databaseEdition, 'STANDARD');
  return ctx;
}
async function readExisting(ctx) {
  const prefix = P.BASE + '/documents/' + COLLECTION + '/';
  const docs = []; let pageToken;
  do {
    const body = (await ctx.firestore.get('/' + P.BASE + '/documents/' + COLLECTION, {queryParams: {pageSize: 300, ...(pageToken ? {pageToken} : {})}})).body;
    for (const d of body.documents || []) {
      C.assert(d.name.startsWith(prefix));
      docs.push({id: d.name.slice(prefix.length), data: decode({mapValue: {fields: d.fields || {}}}), updateTime: d.updateTime});
    }
    pageToken = body.nextPageToken;
  } while (pageToken);
  return docs.sort((a, b) => a.id.localeCompare(b.id));
}
const summary = (items, price) => ({target: C.TARGET, databaseId: P.DATABASE, collection: COLLECTION,
  add: items.filter(i => !i.exists).map(i => i.name), update: items.filter(i => i.exists).map(i => i.name + ' ' + JSON.stringify(i.patch)),
  defaultPriceForTestsWithoutOne: price, existingPricesChanged: 0, deletes: 0});

async function main() {
  const action = process.argv[2]; C.assert(['review', 'apply', 'verify'].includes(action), 'Use review, apply or verify');
  const ctx = await context();
  if (action === 'review') {
    const price = parsePrice(process.argv.slice(3));
    const items = plan(await readExisting(ctx), {price});
    await C.save(RECEIPT, {target: C.TARGET, databaseId: P.DATABASE, at: new Date().toISOString(), price, items});
    console.log(JSON.stringify({...summary(items, price), cloudWrites: 0}, null, 1)); return;
  }
  const review = await C.read(C.path.join(C.OUT, RECEIPT));
  C.assert.equal(review.target, C.TARGET); C.assert.equal(review.databaseId, P.DATABASE);
  if (action === 'apply') {
    C.assert(Date.now() - Date.parse(review.at) < 3600000, 'Review again: the saved review is older than an hour');
    C.same(plan(await readExisting(ctx), {price: review.price}), review.items, 'Lab tests changed since the review; run review again');
    const doc = '/' + P.BASE + '/documents/';
    const writes = review.items.map(i => ({
      update: {name: doc.slice(1) + i.path, fields: P.fields(i.patch)},
      updateMask: {fieldPaths: Object.keys(i.patch)},
      currentDocument: i.exists ? {updateTime: i.updateTime} : {exists: false}}));
    if (writes.length) await ctx.post('/' + P.BASE + '/documents:commit', {writes});
  }
  const after = new Map((await readExisting(ctx)).map(d => [COLLECTION + '/' + d.id, d.data]));
  for (const i of review.items) for (const [k, v] of Object.entries(i.patch)) C.same(after.get(i.path)?.[k], v, 'Unexpected value for ' + i.path + ' ' + k);
  const result = {...summary(review.items, review.price), at: new Date().toISOString(), verifiedDocuments: review.items.length, totalLabTests: after.size};
  await C.save(DONE, result); console.log(JSON.stringify(result, null, 1));
}
if (require.main === module) main().catch(e => {console.error(e.code === 'ERR_ASSERTION' ? e.message : 'Lab test catalogue step failed; nothing printed that is private.'); process.exitCode = 1;});
module.exports = {TESTS, SAME_AS, plan, slug, decode, parsePrice};
