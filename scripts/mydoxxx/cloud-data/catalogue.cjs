// Portable, owner-triggered catalogue operations for the synthetic database only.
// Credentials are short-lived bearer tokens supplied by WIF; never persisted.
// Importing the existing planner does not call its Windows-only adminContext.
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const {isDeepStrictEqual} = require('node:util');
const catalogue = require('../test-lab-lab-tests.cjs');

const TARGET = 'mydoxxx-dev-261102';
const DATABASE = 'mydoxxx-testing';
const BASE = `projects/${TARGET}/databases/${DATABASE}`;
const DEFAULT_BASE = `projects/${TARGET}/databases/(default)`;
const COLLECTION = 'lab_tests';
const REPOSITORY = 'shrinath4all-del/MYDOXXX';
const WORKFLOW = `${REPOSITORY}/.github/workflows/mydoxxx-data.yml@refs/heads/main`;
const MAX_AGE_MS = 24 * 60 * 60 * 1000;
const OUT = 'cloud-data-output';
const INPUT = 'cloud-data-input/plan.json';
const SCHEMA = 'mydoxxx-lab-catalogue-plan-v1';

function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value !== null && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  const encoded = JSON.stringify(value);
  assert.notEqual(encoded, undefined, 'Unsupported value in plan');
  return encoded;
}
function digest(value) { return crypto.createHash('sha256').update(canonical(value)).digest('hex'); }
function strictKeys(object, keys, message) {
  assert(object && typeof object === 'object' && !Array.isArray(object), message);
  assert.deepEqual(Object.keys(object).sort(), [...keys].sort(), message);
}
function requireContext(env) {
  const expected = {
    GITHUB_REPOSITORY: REPOSITORY, GITHUB_REPOSITORY_ID: '1442833578',
    GITHUB_REPOSITORY_OWNER_ID: '281172251', GITHUB_ACTOR_ID: '281172251',
    GITHUB_ACTOR: 'shrinath4all-del', GITHUB_TRIGGERING_ACTOR: 'shrinath4all-del',
    GITHUB_REF: 'refs/heads/main', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_WORKFLOW_REF: WORKFLOW, GITHUB_RUN_ATTEMPT: '1', RUNNER_ENVIRONMENT: 'github-hosted',
  };
  for (const [key, value] of Object.entries(expected)) assert.equal(env[key], value, 'Unapproved workflow context: ' + key);
  assert.match(env.GITHUB_SHA || '', /^[a-f0-9]{40}$/, 'A full source commit is required');
  assert.match(env.GITHUB_RUN_ID || '', /^[1-9][0-9]*$/, 'A workflow run ID is required');
  assert(['preview', 'apply', 'verify'].includes(env.OPERATION), 'Use preview, apply or verify');
  return {repository: REPOSITORY, sha: env.GITHUB_SHA, runId: env.GITHUB_RUN_ID, actorId: env.GITHUB_ACTOR_ID};
}
function parsePrice(value) {
  if (value === undefined || value === '') return null;
  assert.match(value, /^[1-9][0-9]{0,5}$/, 'Default price must be whole rupees from 1 to 100000, or empty');
  const price = Number(value);
  assert(price <= 100000, 'Default price must be whole rupees from 1 to 100000, or empty');
  return price;
}
function validateItems(items) {
  assert(Array.isArray(items) && items.length <= 21, 'Invalid catalogue plan');
  const seen = new Set();
  const allowed = new Set(['name', 'category', 'order', 'time', 'price', 'isActive', 'mydoxSynthetic', 'labMigration']);
  for (const item of items) {
    assert(typeof item.exists === 'boolean', 'Missing existing-document indicator');
    strictKeys(item, ['path', 'name', 'exists', 'patch', ...(item.exists ? ['updateTime'] : [])], 'Unexpected plan item fields');
    assert.match(item.path, /^lab_tests\/[a-z0-9_]+$/i, 'Only direct catalogue records may change');
    assert(!seen.has(item.path), 'Duplicate catalogue record'); seen.add(item.path);
    assert(typeof item.name === 'string' && item.name.length <= 100, 'Invalid catalogue name');
    assert(item.patch && typeof item.patch === 'object' && !Array.isArray(item.patch), 'Invalid catalogue patch');
    const keys = Object.keys(item.patch);
    assert(keys.length > 0 && keys.every(k => allowed.has(k)), 'Unexpected catalogue field');
    for (const value of Object.values(item.patch)) assert(['string', 'number', 'boolean'].includes(typeof value), 'Unexpected field value');
    if (item.exists) assert.match(item.updateTime || '', /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/, 'An exact update precondition is required');
    else { assert.equal(item.patch.mydoxSynthetic, true); assert.equal(item.patch.labMigration, 'lab-tests-v1'); }
    if ('price' in item.patch) assert(Number.isInteger(item.patch.price) && item.patch.price > 0 && item.patch.price <= 100000, 'Invalid catalogue price');
  }
  return items;
}
function safePlan(existing, price) {
  const result = catalogue.plan(existing, {price});
  validateItems(result);
  const before = new Map(existing.map(d => [COLLECTION + '/' + d.id, d]));
  for (const item of result) {
    const original = before.get(item.path);
    assert(!(original?.data.price != null && Object.hasOwn(item.patch, 'price')), 'An existing price must never be overwritten');
  }
  return result;
}
function snapshotDigest(existing) {
  return digest([...existing].sort((a, b) => a.id.localeCompare(b.id)));
}
function makePreview(existing, context, price, now = Date.now()) {
  const unsigned = {schema: SCHEMA, operation: 'preview', target: TARGET, database: DATABASE, collection: COLLECTION,
    repository: context.repository, commit: context.sha, runId: context.runId, runAttempt: '1',
    actorId: context.actorId, createdAt: new Date(now).toISOString(), price,
    snapshotSha256: snapshotDigest(existing), items: safePlan(existing, price)};
  return {...unsigned, sha256: digest(unsigned)};
}
function checkPreview(preview, context, env, existing, now = Date.now()) {
  strictKeys(preview, ['schema', 'operation', 'target', 'database', 'collection', 'repository', 'commit', 'runId', 'runAttempt', 'actorId', 'createdAt', 'price', 'snapshotSha256', 'items', 'sha256'], 'Unexpected preview fields');
  assert.equal(preview.schema, SCHEMA, 'Unsupported plan version');
  assert.equal(preview.operation, 'preview', 'Only a Preview plan can be applied');
  assert.equal(preview.runAttempt, '1', 'Preview must be a first-attempt owner dispatch');
  assert.equal(env.VERIFIED_PREVIEW_ATTEMPT, '1', 'Preview run provenance must be verified');
  assert.equal(preview.target, TARGET, 'Wrong plan project');
  assert.equal(preview.database, DATABASE, 'Wrong plan database');
  assert.equal(preview.collection, COLLECTION, 'Wrong plan collection');
  assert.equal(preview.repository, REPOSITORY, 'Wrong plan repository');
  assert.equal(preview.actorId, '281172251', 'Wrong plan owner');
  assert.equal(preview.commit, context.sha, 'Main changed since preview; create a new preview');
  assert.match(env.PREVIEW_RUN_ID || '', /^[1-9][0-9]*$/, 'A preview run ID is required');
  assert.equal(preview.runId, env.PREVIEW_RUN_ID, 'Wrong preview run');
  assert.notEqual(preview.runId, context.runId, 'Apply must be a separate owner-triggered run');
  assert.match(env.PLAN_SHA256 || '', /^[a-f0-9]{64}$/, 'The approved plan SHA-256 is required');
  assert.match(preview.sha256 || '', /^[a-f0-9]{64}$/, 'Invalid plan SHA-256');
  assert.equal(preview.sha256, env.PLAN_SHA256, 'Plan differs from the approved SHA-256');
  const {sha256, ...unsigned} = preview;
  assert.equal(digest(unsigned), sha256, 'Plan content was changed');
  assert(typeof preview.createdAt === 'string' && Number.isFinite(Date.parse(preview.createdAt)), 'Invalid preview time');
  const age = now - Date.parse(preview.createdAt);
  assert(age >= 0 && age <= MAX_AGE_MS, 'Preview expired or is from the future; preview again');
  assert(preview.price === null || parsePrice(String(preview.price)) === preview.price, 'Invalid preview price');
  assert.equal(preview.snapshotSha256, snapshotDigest(existing), 'Catalogue changed since preview; preview again');
  validateItems(preview.items);
  assert(isDeepStrictEqual(safePlan(existing, preview.price), preview.items), 'Plan no longer matches the approved loader');
  return preview.items;
}
function encode(value) {
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'boolean') return {booleanValue: value};
  assert(Number.isFinite(value), 'Only finite numeric fields may be written');
  return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
}
function toWrites(items) {
  return validateItems(items).map(item => ({
    update: {name: BASE + '/documents/' + item.path, fields: Object.fromEntries(Object.entries(item.patch).map(([key, value]) => [key, encode(value)]))},
    updateMask: {fieldPaths: Object.keys(item.patch)},
    currentDocument: item.exists ? {updateTime: item.updateTime} : {exists: false},
  }));
}

function createApi(token, fetchImpl = fetch) {
  assert(typeof token === 'string' && token.length > 20 && !/[\r\n]/.test(token), 'A temporary Google access token is required');
  async function request(method, resource, body) {
    const allowedGet = resource === BASE || resource === DEFAULT_BASE ||
      resource === BASE + '/documents/lab_tests' ||
      new RegExp('^' + BASE + '/documents/lab_tests\\?pageSize=300(?:&pageToken=[A-Za-z0-9._~!()*%\x27-]+)?$').test(resource);
    const allowedPost = resource === BASE + '/documents:commit';
    assert((method === 'GET' && allowedGet) || (method === 'POST' && allowedPost), 'Firestore API path outside the catalogue operation');
    if (method === 'POST') {
      strictKeys(body, ['writes'], 'Only an atomic catalogue commit is permitted');
      assert(Array.isArray(body.writes) && body.writes.length > 0 && body.writes.length <= 21, 'Invalid write count');
      for (const write of body.writes) {
        strictKeys(write, ['update', 'updateMask', 'currentDocument'], 'Only preconditioned updates are allowed');
        strictKeys(write.update, ['name', 'fields'], 'Unexpected update fields');
        strictKeys(write.updateMask, ['fieldPaths'], 'Every update requires a field mask');
        assert.match(write.update?.name || '', new RegExp('^' + BASE + '/documents/lab_tests/[a-zA-Z0-9_]+$'), 'Write target outside catalogue');
        assert(write.update.fields && typeof write.update.fields === 'object', 'Update fields are required');
        assert.deepEqual([...write.updateMask.fieldPaths].sort(), Object.keys(write.update.fields).sort(), 'Field mask must match the patch');
        if (Object.hasOwn(write.currentDocument, 'exists')) {
          strictKeys(write.currentDocument, ['exists'], 'Invalid create precondition');
          assert.equal(write.currentDocument.exists, false, 'Creates must require nonexistence');
        } else {
          strictKeys(write.currentDocument, ['updateTime'], 'Updates require an exact update time');
          assert.match(write.currentDocument.updateTime || '', /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/, 'Invalid update precondition');
        }
      }
    }
    let response;
    try {
      response = await fetchImpl('https://firestore.googleapis.com/v1/' + resource, {
        method, headers: {Authorization: 'Bearer ' + token, ...(body ? {'Content-Type': 'application/json'} : {})},
        ...(body ? {body: JSON.stringify(body)} : {}), redirect: 'error', signal: AbortSignal.timeout(30000),
      });
    } catch { throw Error('Firestore network request failed; no response or credentials were logged. Verify before retrying an apply.'); }
    if (!response.ok) { const error = Error('Firestore request failed with HTTP ' + response.status); error.status = response.status; throw error; }
    try { return await response.json(); } catch { throw Error('Firestore returned an invalid response'); }
  }
  return {request};
}
async function assertIsolation(api) {
  const database = await api.request('GET', BASE);
  assert.equal(database.name, BASE, 'Wrong Firestore database');
  assert.equal(database.databaseEdition, 'STANDARD', 'Expected Standard edition');
  let denied = false;
  try { await api.request('GET', DEFAULT_BASE); } catch (error) { if (error.status === 403) denied = true; else throw error; }
  assert(denied, 'Protected default database is accessible: stop and correct IAM before running');
  return {databaseEdition: 'STANDARD', defaultDatabaseDenied: true};
}
async function readExisting(api) {
  const prefix = BASE + '/documents/lab_tests/';
  const existing = [], ids = new Set(), pages = new Set();
  let pageToken = '';
  do {
    assert(pages.size < 100 && !pages.has(pageToken), 'Invalid catalogue pagination'); pages.add(pageToken);
    const result = await api.request('GET', BASE + '/documents/lab_tests?pageSize=300' + (pageToken ? '&pageToken=' + encodeURIComponent(pageToken) : ''));
    assert(result.documents === undefined || Array.isArray(result.documents), 'Invalid catalogue response');
    for (const doc of result.documents || []) {
      assert(typeof doc.name === 'string' && doc.name.startsWith(prefix), 'A record belongs to another collection');
      const id = doc.name.slice(prefix.length);
      assert(id && !id.includes('/') && !ids.has(id), 'Invalid or duplicate catalogue record'); ids.add(id);
      existing.push({id, data: catalogue.decode({mapValue: {fields: doc.fields || {}}}), updateTime: doc.updateTime});
    }
    assert(result.nextPageToken === undefined || typeof result.nextPageToken === 'string', 'Invalid page token');
    pageToken = result.nextPageToken || '';
  } while (pageToken);
  return existing.sort((a, b) => a.id.localeCompare(b.id));
}
function describe(existing) {
  const groups = {neuro: 0, blood: 0, other: 0, ungrouped: 0};
  let synthetic = 0;
  for (const doc of existing) { groups[Object.hasOwn(groups, doc.data.category) ? doc.data.category : 'ungrouped']++; if (doc.data.mydoxSynthetic === true) synthetic++; }
  return {totalLabTests: existing.length, syntheticRecords: synthetic, groups};
}
function changes(items) { return {adds: items.filter(i => !i.exists).length, updates: items.filter(i => i.exists).length, deletes: 0, existingPricesChanged: 0}; }
function verifyAfter(existing, after, items) {
  const actual = new Map(after.map(doc => [COLLECTION + '/' + doc.id, doc]));
  for (const item of items) for (const [key, value] of Object.entries(item.patch)) assert(isDeepStrictEqual(actual.get(item.path)?.data[key], value), 'Post-apply verification failed');
  for (const original of existing) {
    const current = actual.get(COLLECTION + '/' + original.id);
    assert(current, 'An existing record is missing after apply');
    if (original.data.price != null) assert.equal(current.data.price, original.data.price, 'An existing price changed during apply; investigate the concurrent writer');
  }
}
function stepSummary(report, preview) {
  let text = '## MyDox cloud database ' + report.operation + '\n\n' +
    '- Target: `' + TARGET + '` / `' + DATABASE + '`\n' +
    '- Source: `' + report.sourceCommit + '`\n' +
    '- Lab tests: ' + report.totalLabTests + '; adds: ' + report.adds + '; updates: ' + report.updates + '; deletes: 0.\n' +
    '- Existing prices changed: 0. Protected default database: access denied.\n' +
    '- Firestore writes in this run: ' + report.cloudWrites + '.\n';
  if (preview) {
    text += '\n### Review before applying\n\nPreview run ID: `' + preview.runId + '`\n\nPlan SHA-256: `' + preview.sha256 + '`\n\n';
    if (!preview.items.length) text += 'No changes are needed. No Apply run is necessary.\n';
    else {
      text += 'The private `mydoxxx-data-preview` artifact contains exactly these changes. For Apply, copy the run ID and SHA-256 above. The preview expires in 24 hours and fails if main or catalogue data changes.\n\n';
      for (const item of preview.items) text += '- ' + (item.exists ? 'Update' : 'Add') + ' `' + item.path + '`: `' + JSON.stringify(item.patch).replace(/`/g, '') + '`\n';
    }
  }
  return text;
}
async function run({env = process.env, fetchImpl = fetch, filesystem = fs, cwd = process.cwd(), now = () => Date.now(), log = console.log} = {}) {
  const context = requireContext(env);
  const operation = env.OPERATION;
  const price = parsePrice(env.DEFAULT_PRICE);
  assert(operation === 'preview' || price === null, 'Set the default price during Preview only');
  const api = createApi(env.GOOGLE_OAUTH_ACCESS_TOKEN, fetchImpl);
  const isolation = await assertIsolation(api);
  const before = await readExisting(api);
  let preview, items = [], cloudWrites = 0;
  if (operation === 'preview') { preview = makePreview(before, context, price, now()); items = preview.items; }
  else if (operation === 'apply') {
    const buffer = await filesystem.readFile(path.join(cwd, INPUT), 'utf8');
    assert(Buffer.byteLength(buffer, 'utf8') <= 256000, 'Unexpected plan size');
    preview = JSON.parse(buffer);
    items = checkPreview(preview, context, env, before, now());
    const writes = toWrites(items);
    if (writes.length) { await api.request('POST', BASE + '/documents:commit', {writes}); cloudWrites = writes.length; }
  }
  const after = operation === 'apply' ? await readExisting(api) : before;
  if (operation === 'apply') verifyAfter(before, after, items);
  const report = {operation, target: TARGET, database: DATABASE, sourceCommit: context.sha,
    runId: context.runId, verifiedAt: new Date(now()).toISOString(), ...isolation, ...describe(after), ...changes(items), cloudWrites,
    ...(preview ? {previewRunId: preview.runId, planSha256: preview.sha256} : {})};
  await filesystem.mkdir(path.join(cwd, OUT), {recursive: true});
  if (operation === 'preview') await filesystem.writeFile(path.join(cwd, OUT, 'plan.json'), JSON.stringify(preview, null, 2) + '\n');
  await filesystem.writeFile(path.join(cwd, OUT, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  const summary = stepSummary(report, operation === 'preview' ? preview : null);
  await filesystem.writeFile(path.join(cwd, OUT, 'summary.md'), summary);
  if (env.GITHUB_STEP_SUMMARY) await filesystem.appendFile(env.GITHUB_STEP_SUMMARY, summary);
  log(JSON.stringify(report));
  return report;
}
if (require.main === module) run().catch(error => {
  // Assertion operands and transport response bodies may contain data or tokens.
  // Print only a controlled failure category, never errors/stacks from fetch.
  const kind = error.code === 'ERR_ASSERTION' ? 'Validation rejected the operation' : 'Cloud catalogue operation failed';
  console.error(kind + '. No credentials or response bodies were logged. Review the inputs and permissions; verify before retrying Apply.');
  process.exitCode = 1;
});
module.exports = {TARGET, DATABASE, BASE, DEFAULT_BASE, REPOSITORY, WORKFLOW, MAX_AGE_MS,
  canonical, digest, requireContext, parsePrice, validateItems, safePlan, snapshotDigest, makePreview, checkPreview,
  toWrites, createApi, assertIsolation, readExisting, describe, verifyAfter, stepSummary, run, main: run, validateContext: requireContext};
