// Evaluate source and mocked requests only. No rulesets/releases or app writes.
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const C = require('../../../scripts/mydoxxx/common.cjs');
const P = require('../../../scripts/mydoxxx/test-lab-plan.cjs');
const legacyCases = require('../../../scripts/mydoxxx/test-lab-rule-check.cjs').cases;
const NOW = Date.parse('2026-11-04T12:00:00.000Z');
const TTL = 28_800_000;
const TIME = new Date(NOW).toISOString();
const RULE_FILE = path.join(__dirname, 'firestore.rules');

function cloudClaims(account, extra = {}) {
  return {...P.claims(account), cloudLab: true, labOperatorUid: 'allowedOwner',
    labIssuedAt: NOW - 1000, labExpiresAt: NOW - 1000 + TTL, ...extra};
}

function cases() {
  const tests = legacyCases().map(t => ({...t, request: {...t.request, time: TIME}}));
  function add(label, expectation, claims, {account = P.ACCOUNTS[0], database = P.DATABASE,
      method = 'get', uid = account.uid} = {}) {
    tests.push({label, expectation, request: {
      path: `/databases/${database}/documents/lab_metadata/config`, method,
      time: TIME, auth: {uid, token: claims}, resource: {data: {syntheticOnly: true}}
    }, resource: {data: {syntheticOnly: true}}, pathEncoding: 'PLAIN'});
  }
  for (const account of P.ACCOUNTS) {
    add('cloud-valid-' + account.key, 'ALLOW', cloudClaims(account), {account});
    add('cloud-expired-' + account.key, 'DENY', cloudClaims(account, {
      labIssuedAt: NOW - TTL, labExpiresAt: NOW
    }), {account});
  }
  const account = P.ACCOUNTS[0], valid = cloudClaims(account);
  for (const method of ['get', 'list', 'create', 'update', 'delete']) {
    add('cloud-valid-' + method, 'ALLOW', valid, {method});
    add('cloud-expired-' + method, 'DENY', {...valid, labExpiresAt: NOW}, {method});
    add('cloud-default-denied-' + method, 'DENY', valid, {method, database: '(default)'});
  }
  for (const [label, changed] of [
    ['false', {cloudLab: false}], ['string-true', {cloudLab: 'true'}],
    ['number-true', {cloudLab: 1}], ['null-marker', {cloudLab: null}],
    ['string-issued', {labIssuedAt: String(NOW)}],
    ['string-expiry', {labExpiresAt: String(NOW + 1000)}],
    ['fractional-issued', {labIssuedAt: NOW - 0.5}],
    ['fractional-expiry', {labExpiresAt: NOW + 0.5}],
    ['future-issued', {labIssuedAt: NOW + 1, labExpiresAt: NOW + 1001}],
    ['expired', {labExpiresAt: NOW - 1}],
    ['too-long', {labIssuedAt: NOW, labExpiresAt: NOW + TTL + 1}],
    ['negative-window', {labIssuedAt: NOW + 1000, labExpiresAt: NOW + 999}],
    ['wrong-role', {role: 'admin'}], ['wrong-marker', {mydoxTest: false}],
    ['wrong-database', {testDatabase: '(default)'}]
  ]) add('cloud-denied-' + label, 'DENY', {...valid, ...changed});
  for (const key of ['labIssuedAt', 'labExpiresAt']) {
    const missing = {...valid}; delete missing[key];
    add('cloud-missing-' + key, 'DENY', missing);
  }
  add('cloud-exact-eight-hours', 'ALLOW', {...valid, labIssuedAt: NOW, labExpiresAt: NOW + TTL});
  add('cloud-last-millisecond', 'ALLOW', {...valid, labIssuedAt: NOW - 1000, labExpiresAt: NOW + 1});
  add('cloud-unknown-uid', 'DENY', valid, {uid: 'unexpectedtestuser'});
  add('cloud-owner-google-not-role', 'DENY', {...valid, email_verified: true,
    firebase: {sign_in_provider: 'google.com'}}, {uid: 'allowedOwner'});
  add('cloud-lookalike-database', 'DENY', valid, {database: P.DATABASE + '-other'});
  return tests;
}

async function offline() {
  const source = await fs.readFile(RULE_FILE, 'utf8');
  assert.equal(P.ACCOUNTS.length, 36);
  const extract = text => JSON.parse(text.match(/let roles = (\{[^\n]+\});/)[1]);
  assert.deepEqual(extract(source), extract(P.rules()), 'The exact role allowlist changed');
  assert(source.includes("database == 'mydoxxx-testing'"));
  assert(source.includes('&& validCloudWindow();'));
  assert(source.includes('request.auth.token.labIssuedAt is int'));
  assert(source.includes('request.auth.token.labExpiresAt is int'));
  assert(source.includes('request.auth.token.labExpiresAt > request.time.toMillis()'));
  assert(!/\bget\(|\bexists\(/.test(source), 'Unexpected live document lookup in these mocked tests');
  const plan = cases();
  assert.equal(new Set(plan.map(x => x.label)).size, plan.length);
  assert(plan.every(t => t.request.time === TIME));
  return {source, plan};
}

async function remote(source, plan) {
  const connected = await C.session();
  const api = connected.api('firebaserules.googleapis.com', 'v1');
  const firestore = connected.api('firestore.googleapis.com', 'v1');
  const database = (await firestore.get(`/projects/${C.TARGET}/databases/${P.DATABASE}`)).body;
  assert.equal(database.databaseEdition, 'STANDARD');
  async function releases() {
    const output = {};
    for (const id of ['cloud.firestore', 'cloud.firestore/' + P.DATABASE]) {
      const name = `projects/${C.TARGET}/releases/${id}`;
      const release = (await api.get('/' + name)).body;
      output[id] = {name: release.name, rulesetName: release.rulesetName};
    }
    return output;
  }
  const before = await releases();
  const result = (await api.post(`/projects/${C.TARGET}:test`, {
    source: {files: [{name: 'firestore.rules', content: source}]},
    testSuite: {testCases: plan.map(({label, ...test}) => test)}
  })).body;
  const after = await releases();
  assert.deepEqual(after, before, 'A deployed rules release changed during the test');
  const report = {target: C.TARGET, databaseId: P.DATABASE, databaseEdition: database.databaseEdition,
    testedAt: new Date().toISOString(), sourceSha256: C.sha(source), mockedRequestTime: TIME,
    cloudRecordsWritten: 0, ruleReleasesChanged: 0, deployedRulesUnchanged: true,
    issues: result.issues || [], tests: plan.map((p, i) => ({name: p.label,
      expectation: p.expectation, state: result.testResults?.[i]?.state || 'MISSING',
      debugMessages: result.testResults?.[i]?.debugMessages || []}))};
  await C.save('cloud-test-room-rule-test.json', report);
  assert.equal(report.tests.length, plan.length);
  assert(!report.issues.some(i => i.severity === 'ERROR'), 'Rules compilation failed; inspect private report');
  assert(report.tests.every(t => t.state === 'SUCCESS'), 'Rule expectation failed; inspect private report');
  return {target: C.TARGET, databaseId: P.DATABASE, sourceSha256: report.sourceSha256,
    passed: report.tests.length, cloudRecordsWritten: 0, ruleReleasesChanged: 0};
}

async function main() {
  const {source, plan} = await offline();
  if (process.argv.includes('--remote')) console.log(JSON.stringify(await remote(source, plan)));
  else console.log(JSON.stringify({mode: 'offline-contract-only', casesPrepared: plan.length,
    exactSyntheticIdentities: 36, sourceSha256: C.sha(source), cloudRequests: 0}));
}
if (require.main === module) main().catch(error => {
  console.error('Cloud test-room rule check stopped: ' + (error.code === 'ERR_ASSERTION' ? error.message :
    error.status || error.code || error.name)); process.exitCode = 1;
});
module.exports = {cases, cloudClaims, offline};
