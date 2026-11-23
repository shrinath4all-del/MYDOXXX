'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const M = require('./catalogue.cjs');
const NOW = Date.parse('2026-11-23T12:00:00Z');
const STAMP = '2026-11-23T11:00:00.123456Z';
const TOKEN = 'temporary-test-token-never-log-this';
const env = (overrides = {}) => ({
  GITHUB_REPOSITORY: 'shrinath4all-del/MYDOXXX', GITHUB_REPOSITORY_ID: '1442833578',
  GITHUB_REPOSITORY_OWNER_ID: '281172251', GITHUB_ACTOR_ID: '281172251',
  GITHUB_ACTOR: 'shrinath4all-del', GITHUB_TRIGGERING_ACTOR: 'shrinath4all-del',
  GITHUB_REF: 'refs/heads/main', GITHUB_EVENT_NAME: 'workflow_dispatch',
  GITHUB_WORKFLOW_REF: M.WORKFLOW, GITHUB_SHA: 'b'.repeat(40), GITHUB_RUN_ID: '1001',
  GITHUB_RUN_ATTEMPT: '1', RUNNER_ENVIRONMENT: 'github-hosted',
  GOOGLE_OAUTH_ACCESS_TOKEN: TOKEN, OPERATION: 'preview', DEFAULT_PRICE: '', ...overrides,
});
const context = overrides => M.requireContext(env(overrides));
const seeded = () => [
  {id: 'cbc', data: {name: 'CBC', price: 350, isActive: true, order: 1, mydoxSynthetic: true}, updateTime: STAMP},
  {id: 'ecg', data: {name: 'ECG', price: 450, isActive: true, order: 2, mydoxSynthetic: true}, updateTime: STAMP},
];
function applyEnv(plan, overrides = {}) {
  return env({OPERATION: 'apply', GITHUB_RUN_ID: '1002', PREVIEW_RUN_ID: '1001',
    PLAN_SHA256: plan.sha256, VERIFIED_PREVIEW_ATTEMPT: '1', ...overrides});
}
function resign(preview) { const {sha256, ...unsigned} = preview; return {...unsigned, sha256: M.digest(unsigned)}; }
function complete() {
  const docs = seeded();
  for (const item of M.safePlan(docs, 500)) {
    const found = docs.find(d => 'lab_tests/' + d.id === item.path);
    if (found) Object.assign(found.data, item.patch);
    else docs.push({id: item.path.split('/')[1], data: item.patch, updateTime: STAMP});
  }
  return docs;
}
function encode(value) {
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (value === null) return {nullValue: null};
  if (typeof value === 'number') return {integerValue: String(value)};
  return {mapValue: {fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encode(v)]))}};
}
function decode(value) { return require('../test-lab-lab-tests.cjs').decode(value); }
function harness(initial = seeded(), options = {}) {
  const docs = structuredClone(initial), calls = [], files = new Map(), logs = [];
  const root = path.resolve('cloud-catalogue-test-no-disk');
  const response = (status, json) => ({status, ok: status >= 200 && status < 300, json: async () => json});
  const fetchImpl = async (url, init) => {
    calls.push({url, method: init.method, body: init.body ? JSON.parse(init.body) : undefined});
    assert.equal(init.headers.Authorization, 'Bearer ' + TOKEN);
    assert.equal(init.redirect, 'error');
    const resource = url.slice('https://firestore.googleapis.com/v1/'.length);
    if (resource === M.BASE) return response(200, {name: M.BASE, databaseEdition: options.edition || 'STANDARD'});
    if (resource === M.DEFAULT_BASE) return response(options.defaultStatus ?? 403, {error: {message: 'PRIVATE-RESPONSE-DO-NOT-PRINT'}});
    if (resource.startsWith(M.BASE + '/documents/lab_tests?')) return response(200, {documents: docs.map(d => ({name: M.BASE + '/documents/lab_tests/' + d.id, updateTime: d.updateTime, fields: Object.fromEntries(Object.entries(d.data).map(([k, v]) => [k, encode(v)]))}))});
    if (resource === M.BASE + '/documents:commit') {
      if (options.race) return response(409, {error: {message: 'PRIVATE-CONFLICT'}});
      const {writes} = JSON.parse(init.body);
      for (const write of writes) {
        const id = write.update.name.split('/').at(-1), found = docs.find(d => d.id === id);
        if (found) assert.equal(write.currentDocument.updateTime, found.updateTime);
        else assert.deepEqual(write.currentDocument, {exists: false});
      }
      for (const write of writes) {
        const id = write.update.name.split('/').at(-1), found = docs.find(d => d.id === id);
        const patch = Object.fromEntries(Object.entries(write.update.fields).map(([k, v]) => [k, decode(v)]));
        if (found) { Object.assign(found.data, patch); found.updateTime = '2026-11-23T12:00:01Z'; }
        else docs.push({id, data: patch, updateTime: '2026-11-23T12:00:01Z'});
      }
      return response(200, {commitTime: '2026-11-23T12:00:01Z'});
    }
    throw Error('Unexpected request');
  };
  const filesystem = {
    mkdir: async () => {},
    readFile: async file => { assert(files.has(file), 'missing fake input'); return files.get(file); },
    writeFile: async (file, value) => files.set(file, value),
    appendFile: async (file, value) => files.set(file, (files.get(file) || '') + value),
  };
  const input = plan => files.set(path.join(root, 'cloud-data-input', 'plan.json'), JSON.stringify(plan));
  const output = filename => JSON.parse(files.get(path.join(root, 'cloud-data-output', filename)));
  const run = runtimeEnv => M.run({env: runtimeEnv, fetchImpl, filesystem, cwd: root, now: () => NOW, log: v => logs.push(v)});
  return {docs, calls, files, logs, input, output, run, fetchImpl};
}

test('owner dispatch guard rejects every wrong identity, branch, event and runner before using credentials', () => {
  assert.equal(context().actorId, '281172251');
  const wrong = {GITHUB_REPOSITORY: 'somebody/MYDOXXX', GITHUB_REPOSITORY_ID: '1', GITHUB_REPOSITORY_OWNER_ID: '2',
    GITHUB_ACTOR_ID: '3', GITHUB_ACTOR: 'other', GITHUB_TRIGGERING_ACTOR: 'collaborator', GITHUB_REF: 'refs/heads/feature',
    GITHUB_EVENT_NAME: 'push', GITHUB_WORKFLOW_REF: M.WORKFLOW.replace('mydoxxx-data', 'other'), GITHUB_RUN_ATTEMPT: '2',
    RUNNER_ENVIRONMENT: 'self-hosted', GITHUB_SHA: 'main', GITHUB_RUN_ID: 'x', OPERATION: 'delete'};
  for (const [key, value] of Object.entries(wrong)) assert.throws(() => context({[key]: value}), key);
});

test('a preview preserves existing prices and contains no raw private catalogue fields or token', async () => {
  const docs = seeded(); docs.push({id: 'private_custom', data: {name: 'Private custom', price: 999, note: 'PRIVATE-NOTE'}, updateTime: STAMP});
  const h = harness(docs);
  const report = await h.run(env({DEFAULT_PRICE: '500'}));
  assert.equal(report.adds, 19); assert.equal(report.updates, 2); assert.equal(report.cloudWrites, 0);
  const preview = h.output('plan.json');
  assert.equal(preview.operation, 'preview'); assert.equal(preview.commit, 'b'.repeat(40));
  assert.equal(preview.runId, '1001'); assert.equal(preview.runAttempt, '1');
  assert(preview.items.filter(i => i.exists).every(i => !('price' in i.patch)));
  const allOutput = JSON.stringify([...h.files.values(), h.logs]);
  for (const secret of [TOKEN, 'PRIVATE-NOTE', 'private_custom', 'PRIVATE-RESPONSE']) assert(!allOutput.includes(secret));
  assert(!h.calls.some(c => c.method === 'POST'));
});

test('apply uses one atomic preconditioned commit and reads back every changed value', async () => {
  const h = harness();
  const preview = M.makePreview(seeded(), context(), 500, NOW); h.input(preview);
  const report = await h.run(applyEnv(preview));
  const writes = h.calls.filter(c => c.method === 'POST');
  assert.equal(writes.length, 1); assert.equal(writes[0].body.writes.length, 21);
  assert.equal(writes[0].body.writes.filter(w => w.currentDocument.exists === false).length, 19);
  assert.equal(writes[0].body.writes.filter(w => w.currentDocument.updateTime === STAMP).length, 2);
  assert(writes[0].body.writes.every(w => !w.delete && w.update.name.startsWith(M.BASE + '/documents/lab_tests/')));
  assert.equal(report.cloudWrites, 21); assert.equal(report.totalLabTests, 21);
  assert.equal(h.docs.find(d => d.id === 'cbc').data.price, 350);
  assert.equal(h.docs.find(d => d.id === 'ecg').data.price, 450);
  assert.equal(M.safePlan(h.docs, 500).length, 0);
});

test('stale, future and different-commit previews are rejected before any write', async () => {
  for (const time of [NOW - M.MAX_AGE_MS - 1, NOW + 1]) {
    const h = harness(), preview = M.makePreview(seeded(), context(), 500, time); h.input(preview);
    await assert.rejects(h.run(applyEnv(preview)), /expired|future/);
    assert(!h.calls.some(c => c.method === 'POST'));
  }
  const h = harness(), preview = M.makePreview(seeded(), context(), 500, NOW); h.input(preview);
  await assert.rejects(h.run(applyEnv(preview, {GITHUB_SHA: 'a'.repeat(40)})), /Main changed/);
  assert(!h.calls.some(c => c.method === 'POST'));
});

test('exact approved run, provenance and typed SHA256 are required', () => {
  const preview = M.makePreview(seeded(), context(), null, NOW);
  const runtime = applyEnv(preview), ctx = M.requireContext(runtime);
  for (const extra of [{PREVIEW_RUN_ID: ''}, {PREVIEW_RUN_ID: '9'}, {PLAN_SHA256: ''}, {PLAN_SHA256: '1'.repeat(64)},
    {VERIFIED_PREVIEW_ATTEMPT: undefined}, {VERIFIED_PREVIEW_ATTEMPT: '2'}]) {
    assert.throws(() => M.checkPreview(preview, ctx, {...runtime, ...extra}, seeded(), NOW));
  }
  assert.throws(() => M.checkPreview(preview, {...ctx, runId: preview.runId}, runtime, seeded(), NOW), /separate/);
});

test('tampering is rejected even when the modified plan has a recomputed digest', () => {
  const original = M.makePreview(seeded(), context(), 500, NOW);
  const corrupt = structuredClone(original); corrupt.items[0].patch.price = 99;
  assert.throws(() => M.checkPreview(corrupt, context({GITHUB_RUN_ID: '1002'}), applyEnv(original), seeded(), NOW), /changed/);
  for (const mutate of [p => {p.target = 'clinigo-77808';}, p => {p.database = '(default)';},
    p => {p.collection = 'users';}, p => {p.repository = 'other/MYDOXXX';}, p => {p.actorId = '7';},
    p => {p.operation = 'apply';}, p => {p.runAttempt = '2';},
    p => {p.items[0].path = 'users/owner';}, p => {p.items[0].patch.price = 700;},
    p => {p.items[0].patch.extra = 'unexpected';}, p => {p.items.push(structuredClone(p.items[0]));}]) {
    const candidate = structuredClone(original); mutate(candidate); const plan = resign(candidate);
    assert.throws(() => M.checkPreview(plan, context({GITHUB_RUN_ID: '1002'}), applyEnv(plan), seeded(), NOW));
  }
});

test('a concurrent catalogue change between Preview and Apply causes no commit', async () => {
  const preview = M.makePreview(seeded(), context(), 500, NOW), h = harness(); h.input(preview);
  h.docs[0].data.price = 390;
  await assert.rejects(h.run(applyEnv(preview)), /Catalogue changed/);
  assert(!h.calls.some(c => c.method === 'POST'));
  assert.equal(h.docs.length, 2);
});

test('atomic preconditions handle a race after reread; failed commit is not retried or reported as success', async () => {
  const preview = M.makePreview(seeded(), context(), 500, NOW), h = harness(seeded(), {race: true}); h.input(preview);
  await assert.rejects(h.run(applyEnv(preview)), /HTTP 409/);
  assert.equal(h.calls.filter(c => c.method === 'POST').length, 1);
  assert.equal(h.docs.length, 2);
  assert.equal(h.files.size, 1, 'only the input plan exists; no successful report');
  assert.equal(h.logs.length, 0);
});

test('reapplying an old successful plan fails while a newly previewed no-op makes no writes', async () => {
  const preview = M.makePreview(seeded(), context(), 500, NOW), h = harness(complete()); h.input(preview);
  await assert.rejects(h.run(applyEnv(preview)), /Catalogue changed/);
  assert(!h.calls.some(c => c.method === 'POST'));
  const newPreview = M.makePreview(h.docs, context(), 500, NOW); h.input(newPreview);
  const report = await h.run(applyEnv(newPreview));
  assert.equal(report.cloudWrites, 0); assert.equal(report.adds, 0); assert.equal(report.updates, 0);
  assert(!h.calls.some(c => c.method === 'POST'));
});

test('verify is read-only, proves default DB denial, and reports actual catalogue groups', async () => {
  const h = harness(complete()), report = await h.run(env({OPERATION: 'verify'}));
  assert.equal(report.cloudWrites, 0); assert.equal(report.totalLabTests, 21);
  assert.equal(report.syntheticRecords, 21);
  assert.deepEqual(report.groups, {neuro: 8, blood: 7, other: 6, ungrouped: 0});
  assert.equal(report.defaultDatabaseDenied, true);
  assert(h.calls.some(c => c.url.endsWith(M.DEFAULT_BASE)));
  assert(h.calls.every(c => c.method === 'GET'));
});

test('default DB accessible, not-found or unauthenticated responses fail closed before catalogue reads', async () => {
  for (const status of [200, 401, 404, 429, 500]) {
    const h = harness(seeded(), {defaultStatus: status});
    await assert.rejects(h.run(env()));
    assert.equal(h.calls.length, 2); assert.equal(h.files.size, 0);
  }
});

test('wrong database edition fails before any catalogue read or write', async () => {
  const h = harness(seeded(), {edition: 'ENTERPRISE'});
  await assert.rejects(h.run(env()), /Standard/);
  assert.equal(h.calls.length, 1);
});

test('API transport rejects other projects, collections, methods, and unguarded writes', async () => {
  let calls = 0;
  const api = M.createApi(TOKEN, async () => { calls++; throw Error('should not run'); });
  for (const resource of [M.BASE.replace('mydoxxx-dev-261102', 'mydox-be432'), M.DEFAULT_BASE + '/documents/lab_tests',
    M.BASE + '/documents/users', M.BASE + '/documents/lab_tests/abc', 'https://attacker.invalid/']) {
    await assert.rejects(api.request('GET', resource));
  }
  await assert.rejects(api.request('DELETE', M.BASE));
  await assert.rejects(api.request('POST', M.BASE + '/documents:commit', {writes: [{delete: M.BASE + '/documents/lab_tests/a'}]}));
  await assert.rejects(api.request('POST', M.BASE + '/documents:commit', {writes: [{update: {name: M.BASE + '/documents/users/a'}, updateMask: {}, currentDocument: {}}]}));
  assert.equal(calls, 0);
});

test('network and HTTP errors never include bearer tokens or server response bodies', async () => {
  const api = M.createApi(TOKEN, async () => { throw Error(TOKEN); });
  await assert.rejects(api.request('GET', M.BASE), e => !e.message.includes(TOKEN) && e.message.includes('network request failed'));
  const api2 = M.createApi(TOKEN, async () => ({ok: false, status: 403, json: async () => ({token: TOKEN})}));
  await assert.rejects(api2.request('GET', M.BASE), e => e.status === 403 && !e.message.includes(TOKEN));
});

test('pagination uses encoded opaque tokens and rejects duplicates or a foreign record', async () => {
  const requests = [], token = 'x/y&leak?foo';
  const api = {request: async (method, resource) => { requests.push(resource); return requests.length === 1 ? {documents: [], nextPageToken: token} : {documents: []}; }};
  assert.deepEqual(await M.readExisting(api), []);
  assert(requests[1].endsWith('&pageToken=' + encodeURIComponent(token)));
  const foreign = {request: async () => ({documents: [{name: M.DEFAULT_BASE + '/documents/lab_tests/a'}]})};
  await assert.rejects(M.readExisting(foreign), /another collection/);
  const repeating = {request: async () => ({documents: [], nextPageToken: 'same'})};
  await assert.rejects(M.readExisting(repeating), /pagination/);
});

test('price input is explicit, bounded and never accepted on Apply or Verify', async () => {
  for (const bad of ['0', '-2', '1.5', '1e2', '100001', ' 500', '500 ', 'abc']) assert.throws(() => M.parsePrice(bad));
  assert.equal(M.parsePrice('100000'), 100000); assert.equal(M.parsePrice(''), null);
  const h = harness();
  await assert.rejects(h.run(env({OPERATION: 'verify', DEFAULT_PRICE: '500'})), /Preview only/);
  assert.equal(h.calls.length, 0);
});

test('post-apply verification detects missing patches, removed records and unexpected price changes', () => {
  const before = seeded(), items = M.safePlan(before, 500), after = complete();
  assert.doesNotThrow(() => M.verifyAfter(before, after, items));
  const missing = structuredClone(after); missing.find(d => d.id === 'eeg').data.time = 80;
  assert.throws(() => M.verifyAfter(before, missing, items), /verification failed/);
  const price = structuredClone(after); price.find(d => d.id === 'cbc').data.price = 351;
  assert.throws(() => M.verifyAfter(before, price, items), /price changed/);
});

test('digest is independent of key order but binds all content and snapshot update times', () => {
  assert.equal(M.digest({a: 1, b: {y: 2, x: 3}}), M.digest({b: {x: 3, y: 2}, a: 1}));
  const first = M.snapshotDigest(seeded()), changed = seeded(); changed[0].updateTime = '2026-11-23T11:00:01Z';
  assert.notEqual(first, M.snapshotDigest(changed));
  assert.equal(first, M.snapshotDigest(seeded().reverse()));
});
