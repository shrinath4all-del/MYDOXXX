'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const policy = require('../policy.cjs');
const {createHandler} = require('../handler.cjs');
const {PROJECT, DATABASE, OWNER_EMAIL, ROLES, LAB_SESSION_MS, configFromEnv} = policy;
const ORIGIN = 'https://mydoxxx-live-test.netlify.app';
const config = configFromEnv({GCLOUD_PROJECT: PROJECT, MYDOX_CLOUD_ORIGIN: ORIGIN});

function request(roleKey = 'doctor', overrides = {}) {
  return {method: 'POST', url: '/', headers: {origin: ORIGIN, 'content-type': 'application/json',
    authorization: 'Bearer signed.owner.token'}, rawBody: Buffer.from(JSON.stringify({roleKey})), ...overrides};
}
function response() {
  return {headers: {}, statusCode: null, body: null,
    setHeader(k, v) { this.headers[k.toLowerCase()] = v; },
    status(n) { this.statusCode = n; return this; },
    json(body) { this.body = body; return this; }, end() { this.ended = true; return this; }};
}
function decoded(overrides = {}) {
  return {uid: 'ownerGoogleUid', sub: 'ownerGoogleUid', aud: PROJECT,
    iss: `https://securetoken.google.com/${PROJECT}`, email: OWNER_EMAIL,
    email_verified: true, firebase: {sign_in_provider: 'google.com'}, ...overrides};
}
function owner(overrides = {}) {
  return {uid: 'ownerGoogleUid', email: OWNER_EMAIL, emailVerified: true, disabled: false,
    providerData: [{providerId: 'google.com', email: OWNER_EMAIL}], ...overrides};
}
function target(roleKey, overrides = {}) {
  const identity = ROLES[roleKey];
  return {uid: identity.uid, disabled: false,
    customClaims: {mydoxTest: true, testDatabase: DATABASE, role: identity.role}, ...overrides};
}
function setup(options = {}) {
  const calls = [];
  const auth = {
    async verifyIdToken(token, revoked) {
      calls.push(['verify', token, revoked]);
      if (options.verifyError) throw new Error('sensitive server token must never appear');
      return options.decoded || decoded();
    },
    async getUser(uid) {
      calls.push(['getUser', uid]);
      if (options.getError) throw new Error('private record error');
      return uid === 'ownerGoogleUid' ? (options.owner || owner()) : (options.target || target(options.key || 'doctor'));
    },
    async createCustomToken(uid, claims) {
      calls.push(['mint', uid, claims]);
      if (options.mintError) throw new Error('private signing details');
      return 'synthetic.custom.result';
    },
  };
  return {calls, handler: createHandler({getRuntime: () => ({config, auth}), now: () => 1700000000000})};
}
async function run(options = {}, req = request()) {
  const unit = setup(options), res = response(); await unit.handler(req, res); return {...unit, res};
}

test('all 36 catalogue keys map to the exact stable UID and role', () => {
  assert.equal(Object.keys(ROLES).length, 36);
  assert.equal(new Set(Object.values(ROLES).map(r => r.uid)).size, 36);
  for (const [key, identity] of Object.entries(ROLES)) {
    assert.equal(identity.uid, `mdxtest${key.replaceAll('_', '')}`);
    const family = key.replace(/_[23]$/, '');
    assert.equal(identity.role, family.startsWith('agency_') ? 'agency' : family);
  }
});

test('valid owner receives only requested role, with revocation check and fixed eight-hour claims', async () => {
  for (const key of Object.keys(ROLES)) {
    const {res, calls} = await run({key}, request(key));
    assert.equal(res.statusCode, 200);
    assert.equal(calls[0][2], true, 'SDK must check owner revocation');
    assert.deepEqual(calls.slice(1, 3), [['getUser', 'ownerGoogleUid'], ['getUser', ROLES[key].uid]]);
    assert.deepEqual(calls[3], ['mint', ROLES[key].uid, {
      mydoxTest: true, testDatabase: DATABASE, role: ROLES[key].role, cloudLab: true,
      labOperatorUid: 'ownerGoogleUid', labIssuedAt: 1700000000000, labExpiresAt: 1700000000000 + LAB_SESSION_MS,
    }]);
    assert.deepEqual(Object.keys(res.body).sort(), ['customToken', 'databaseId', 'labExpiresAt', 'labIssuedAt', 'projectId', 'role', 'roleKey', 'uid']);
    assert.equal(res.body.uid, ROLES[key].uid);
    assert.match(res.headers['cache-control'], /no-store/);
    assert.equal(res.headers['access-control-allow-origin'], ORIGIN);
  }
});

test('denies anonymous, malformed, duplicated or oversized bearer headers without calling Auth', async () => {
  for (const value of [undefined, '', 'Basic abc', 'Bearer anything', 'Bearer a.b.c,d.e.f', 'Bearer ' + 'a'.repeat(8193) + '.b.c']) {
    const req = request(); req.headers.authorization = value;
    const {res, calls} = await run({}, req); assert.equal(res.statusCode, 401); assert.equal(calls.length, 0);
  }
  const req = request(undefined, {rawHeaders: ['Authorization', 'Bearer a.b.c', 'authorization', 'Bearer d.e.f']});
  const {res, calls} = await run({}, req); assert.equal(res.statusCode, 400); assert.equal(calls.length, 0);
});

test('bad, revoked or expired Google owner token never obtains target identity/token', async () => {
  const {res, calls} = await run({verifyError: true});
  assert.equal(res.statusCode, 401); assert.equal(calls.length, 1);
  assert.deepEqual(res.body, {error: 'sign_in_required'});
});

test('wrong owner/provider/project/verification/tenant cannot mint roles', async () => {
  const variants = [
    {email: 'someone@example.com'}, {email: 'SHRINATH4ALL@gmail.com'}, {email_verified: false},
    {aud: 'mydox-be432'}, {iss: 'https://securetoken.google.com/clinigo-77808'},
    {firebase: {sign_in_provider: 'password'}}, {firebase: {sign_in_provider: 'custom'}},
    {firebase: {sign_in_provider: 'google.com', tenant: 'another'}},
    {uid: 'mdxtestdoctor', sub: 'mdxtestdoctor'}, {sub: 'different'}, {uid: ''},
  ];
  for (const variant of variants) {
    const {res, calls} = await run({decoded: decoded(variant)});
    assert.equal(res.statusCode, 403); assert.equal(calls.length, 1);
  }
});

test('current operator record must remain enabled, verified and linked to allowed Google account', async () => {
  for (const variant of [{disabled: true}, {email: 'changed@example.com'}, {emailVerified: false},
    {providerData: []}, {providerData: [{providerId: 'password', email: OWNER_EMAIL}]}, {tenantId: 'tenant'}]) {
    const {res, calls} = await run({owner: owner(variant)});
    assert.equal(res.statusCode, 403); assert.equal(calls.length, 2);
  }
});

test('test target must already exist, be enabled and have exact existing safe claims', async () => {
  for (const variant of [{disabled: true}, {uid: 'unrelated'}, {customClaims: {}}, {tenantId: 'tenant'},
    {customClaims: {mydoxTest: true, testDatabase: '(default)', role: 'doctor'}},
    {customClaims: {mydoxTest: true, testDatabase: DATABASE, role: 'admin'}},
    {customClaims: {mydoxTest: true, testDatabase: DATABASE, role: 'doctor', admin: true}}]) {
    const {res, calls} = await run({target: target('doctor', variant)});
    assert.equal(res.statusCode, 403); assert.equal(calls.filter(c => c[0] === 'mint').length, 0);
  }
  const {res, calls} = await run({getError: true});
  assert.equal(res.statusCode, 503); assert.equal(calls.filter(c => c[0] === 'mint').length, 0);
});

test('rejects target/claim injection, unsupported keys and oversized/non-JSON bodies', async () => {
  const invalid = [null, [], {}, {roleKey: 'doctor', uid: 'admin'}, {roleKey: 'doctor', claims: {}},
    {roleKey: 'doctor_99'}, {roleKey: '__proto__'}, {roleKey: 'constructor'}, {roleKey: 1},
    {roleKey: 'Doctor'}, {roleKey: 'doctor '}, {roleKey: 'admin'}];
  for (const body of invalid) {
    const {res, calls} = await run({}, request('doctor', {rawBody: Buffer.from(JSON.stringify(body))}));
    assert.equal(res.statusCode, 400); assert.equal(calls.length, 0);
  }
  for (const body of [Buffer.alloc(513), Buffer.from('{'), undefined]) {
    const {res, calls} = await run({}, request('doctor', {rawBody: body}));
    assert.ok([400, 413].includes(res.statusCode)); assert.equal(calls.length, 0);
  }
});

test('exact Origin and preflight are required, without wildcard/credentials CORS', async () => {
  for (const origin of [undefined, 'null', '*', 'http://localhost:8889', ORIGIN + '/', ORIGIN + '.evil.example']) {
    const req = request(); req.headers.origin = origin;
    const {res, calls} = await run({}, req); assert.equal(res.statusCode, 403);
    assert.equal(calls.length, 0); assert.equal(res.headers['access-control-allow-origin'], undefined);
  }
  const req = request('doctor', {method: 'OPTIONS', headers: {origin: ORIGIN,
    'access-control-request-method': 'POST', 'access-control-request-headers': 'content-type, authorization'}});
  const {res, calls} = await run({}, req);
  assert.equal(res.statusCode, 204); assert.equal(calls.length, 0);
  assert.equal(res.headers['access-control-allow-origin'], ORIGIN);
  assert.equal(res.headers['access-control-allow-credentials'], undefined);
  req.headers['access-control-request-headers'] = 'authorization, x-unreviewed';
  assert.equal((await run({}, req)).res.statusCode, 403);
});

test('unsupported methods, content types, encodings, path/query and duplicate origin fail closed', async () => {
  for (const method of ['GET', 'HEAD', 'PUT', 'DELETE']) assert.equal((await run({}, request('doctor', {method}))).res.statusCode, 405);
  for (const [header, value, expected] of [['content-type', 'text/plain', 415], ['content-encoding', 'gzip', 415],
    ['content-length', '999999', 413], ['content-length', '-1', 413]]) {
    const req = request(); req.headers[header] = value;
    assert.equal((await run({}, req)).res.statusCode, expected);
  }
  assert.equal((await run({}, request('doctor', {url: '/?token=bad'}))).res.statusCode, 400);
  assert.equal((await run({}, request('doctor', {rawHeaders: ['Origin', ORIGIN, 'origin', ORIGIN]}))).res.statusCode, 400);
});

test('SDK failures return generic errors and no token or account details', async () => {
  const {res} = await run({mintError: true});
  assert.equal(res.statusCode, 503); assert.deepEqual(res.body, {error: 'temporarily_unavailable'});
  assert.doesNotMatch(JSON.stringify(res), /signed.owner.token|private signing|shrinath4all/);
});

test('config refuses wrong/absent/conflicting projects, emulator and invalid origins', () => {
  const variants = [{}, {GCLOUD_PROJECT: 'mydox-be432'}, {GOOGLE_CLOUD_PROJECT: 'clinigo-77808'},
    {FIREBASE_CONFIG: '{'}, {FIREBASE_CONFIG: JSON.stringify({projectId: 'mydoxxx'})},
    {FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099'},
    {MYDOX_CLOUD_ORIGIN: '*'}, {MYDOX_CLOUD_ORIGIN: ORIGIN + '/'}, {MYDOX_CLOUD_ORIGIN: 'http://example.com'},
    {MYDOX_CLOUD_ORIGIN: 'https://localhost'}, {MYDOX_CLOUD_ORIGIN: 'https://user:pass@example.com'}];
  assert.throws(() => configFromEnv({MYDOX_CLOUD_ORIGIN: ORIGIN}));
  for (const variant of variants.slice(1)) assert.throws(() => configFromEnv({GCLOUD_PROJECT: PROJECT, MYDOX_CLOUD_ORIGIN: ORIGIN, ...variant}));
  assert.equal(configFromEnv({GOOGLE_CLOUD_PROJECT: PROJECT, MYDOX_CLOUD_ORIGIN: ORIGIN}).projectId, PROJECT);
});

test('deployment remains dedicated and contains no recovery/rules/auth setup', () => {
  const root = path.resolve(__dirname, '..');
  const configFile = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json')));
  assert.deepEqual(Object.keys(configFile), ['functions']);
  assert.equal(configFile.functions.length, 1);
  assert.equal(configFile.functions[0].codebase, 'mydoxxx-cloud-lab-broker');
  const src = fs.readFileSync(path.join(root, 'index.js'), 'utf8');
  assert.match(src, /serviceAccount: SERVICE_ACCOUNT/); assert.match(src, /maxInstances: 1/);
  for (const file of ['index.js', 'handler.cjs', 'policy.cjs']) {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    assert.doesNotMatch(text, /console\.|setCustomUserClaims|createUser\(|updateUser\(|deleteUser\(|getFirestore\(|common\.cjs/);
  }
});
