'use strict';
// Read-only deployed endpoint/config checks. Never signs in, mints a real role
// token, changes IAM/data, or logs request/response credentials.
const assert = require('node:assert/strict');
const path = require('node:path');
const {PROJECT, SERVICE_ACCOUNT} = require('../policy.cjs');
const ENDPOINT = `https://us-central1-${PROJECT}.cloudfunctions.net/mintMyDoxLabRole`;
const ORIGIN = 'https://mydoxxx-live-test.netlify.app';

async function httpChecks() {
  const json = {'Content-Type': 'application/json'};
  const cases = [
    {name: 'no_origin', expected: 403, error: 'origin_not_allowed', headers: json, body: {roleKey: 'doctor'}},
    {name: 'approved_origin_missing_auth', expected: 401, error: 'sign_in_required', headers: {...json, Origin: ORIGIN}, body: {roleKey: 'doctor'}},
    {name: 'wrong_origin', expected: 403, error: 'origin_not_allowed', headers: {...json, Origin: 'https://untrusted.example'}, body: {roleKey: 'doctor'}},
    {name: 'expected_preflight', expected: 204, method: 'OPTIONS', headers: {Origin: ORIGIN,
      'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization, content-type'}},
    {name: 'malformed_role', expected: 400, error: 'invalid_role_request', headers: {...json, Origin: ORIGIN}, body: {roleKey: 'admin'}},
  ];
  const results = [];
  for (const item of cases) {
    const res = await fetch(ENDPOINT, {method: item.method || 'POST', headers: item.headers,
      ...(item.body ? {body: JSON.stringify(item.body)} : {}), redirect: 'manual', signal: AbortSignal.timeout(30000)});
    let errorCode = null;
    if (res.status !== 204) {
      let data; try { data = await res.json(); } catch { data = null; }
      errorCode = typeof data?.error === 'string' && /^[a-z_]{1,80}$/.test(data.error) ? data.error : 'unexpected_response';
    }
    const cors = res.headers.get('access-control-allow-origin');
    const expectedCors = item.headers.Origin === ORIGIN ? ORIGIN : null;
    results.push({name: item.name, status: res.status, errorCode, exactCors: cors === expectedCors,
      noStore: (res.headers.get('cache-control') || '').includes('no-store')});
    assert.equal(res.status, item.expected, `${item.name}: unexpected status ${res.status}`);
    if (item.error) assert.equal(errorCode, item.error, `${item.name}: unexpected safe error code`);
    assert.equal(cors, expectedCors, `${item.name}: incorrect CORS header`);
    assert((res.headers.get('cache-control') || '').includes('no-store'), `${item.name}: missing no-store`);
  }
  return results;
}

async function metadataChecks(common) {
  assert.equal(common.TARGET, PROJECT); assert.equal(common.NUMBER, '724915428929');
  common.assertTarget();
  const session = await common.session();
  const functions = session.api('cloudfunctions.googleapis.com', 'v2');
  const listed = (await functions.get(`/projects/${PROJECT}/locations/-/functions`)).body;
  assert(!listed.nextPageToken && !(listed.unreachable || []).length, 'Function list is incomplete');
  const all = listed.functions || [];
  const plan = await common.read(path.join(common.OUT, 'function-experiment-plan.json'));
  assert.equal(plan.target, PROJECT); assert.equal(String(plan.targetProjectNumber), '724915428929');
  const expected = plan.groups.flatMap(g => g.functions).sort();
  assert.equal(expected.length, 36);
  const names = all.map(f => f.name.split('/').pop()).sort();
  assert.deepEqual(names, [...expected, 'mintMyDoxLabRole'].sort(), 'Recovered function names changed or unexpected functions are present');
  const broker = all.find(f => f.name.endsWith('/mintMyDoxLabRole'));
  assert.equal(broker.name, `projects/${PROJECT}/locations/us-central1/functions/mintMyDoxLabRole`);
  assert.equal(broker.state, 'ACTIVE'); assert.equal(broker.buildConfig.runtime, 'nodejs22');
  const service = broker.serviceConfig;
  assert.equal(service.serviceAccountEmail, SERVICE_ACCOUNT);
  assert.equal(service.minInstanceCount || 0, 0); assert.equal(service.maxInstanceCount, 1);
  assert.equal(service.environmentVariables.MYDOX_CLOUD_ORIGIN, ORIGIN);
  const recovered = all.filter(f => !f.name.endsWith('/mintMyDoxLabRole'));
  assert(recovered.every(f => f.state === 'ACTIVE'), 'A recovered function is not ACTIVE');
  assert(recovered.every(f => f.serviceConfig?.environmentVariables?.MYDOX_RECOVERY_MODE === 'true'), 'A recovered guard is missing');
  return {broker: {name: 'mintMyDoxLabRole', state: broker.state, runtime: broker.buildConfig.runtime,
    serviceAccount: service.serviceAccountEmail, minInstances: service.minInstanceCount || 0,
    maxInstances: service.maxInstanceCount, origin: ORIGIN},
  recovered: {expected: 36, found: recovered.length, allActive: true, recoveryGuardsPresent: true, names: expected},
  preservationLimit: 'Names/current ACTIVE/guard state checked; no historical revision or full IAM diff claimed'};
}

async function main() {
  assert(process.argv.length <= 3 && (!process.argv[2] || process.argv[2] === '--http-only'), 'Use optional --http-only');
  const report = {projectId: PROJECT, readOnly: true, startedAt: new Date().toISOString(), signedOwnerTested: false,
    realRoleTokensRequested: false, http: await httpChecks()};
  if (process.argv[2] !== '--http-only') {
    const common = require(path.resolve(__dirname, '../../../../scripts/mydoxxx/common.cjs'));
    report.metadata = await metadataChecks(common);
    report.completedAt = new Date().toISOString();
    await common.save('cloud-test-room-broker-live-check.json', report);
  }
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) main().catch(error => {
  const safe = error instanceof assert.AssertionError ? error.message : 'Read-only HTTP/config check failed; no response or credentials logged';
  console.error(safe); process.exitCode = 2;
});
module.exports = {httpChecks, metadataChecks};
