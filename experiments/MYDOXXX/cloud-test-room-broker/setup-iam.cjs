'use strict';

// Default is read-only. Only an explicit --apply enters resource mutations.
// Runtime index/handler never imports this owner-operated deployment helper.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {PROJECT, SERVICE_ACCOUNT} = require('./policy.cjs');
const NUMBER = '724915428929';
const OWNER = 'shrinath4all@gmail.com';
const MEMBER = `serviceAccount:${SERVICE_ACCOUNT}`;
const ACCOUNT_ID = 'mydoxxx-lab-broker';
const ACCOUNT_RESOURCE = `/projects/${PROJECT}/serviceAccounts/${SERVICE_ACCOUNT}`;
const ROLE_IDS = Object.freeze({auth: 'mydoxLabBrokerAuthRead', sign: 'mydoxLabBrokerSelfSign'});
const ROLE_NAMES = Object.freeze(Object.fromEntries(Object.entries(ROLE_IDS).map(([k, id]) => [k, `projects/${PROJECT}/roles/${id}`])));
const PERMISSIONS = Object.freeze({auth: ['firebaseauth.users.get'], sign: ['iam.serviceAccounts.signBlob']});

function loadCommon() {
  const expectedRoot = path.resolve(__dirname, '../../..');
  const source = path.resolve(__dirname, '../../../scripts/mydoxxx/common.cjs');
  assert.equal(source, path.join(expectedRoot, 'scripts', 'mydoxxx', 'common.cjs'));
  const common = require(source);
  common.assertTarget();
  assert.equal(common.ROOT, expectedRoot, 'Common helper belongs to another workspace');
  assert.equal(common.TARGET, PROJECT); assert.equal(common.NUMBER, NUMBER); assert.equal(common.OWNER, OWNER);
  return common;
}

function roleDefinition(kind) {
  assert(Object.hasOwn(ROLE_IDS, kind));
  const name = kind === 'auth' ? 'auth-read-role.json' : 'self-sign-role.json';
  const def = JSON.parse(fs.readFileSync(path.join(__dirname, 'iam', name), 'utf8'));
  assert.deepEqual([...def.includedPermissions].sort(), [...PERMISSIONS[kind]].sort(), 'Role file contains unapproved permissions');
  assert.equal(def.stage, 'GA');
  return def;
}

function validateRole(role, kind) {
  if (!role) return;
  assert.equal(role.name, ROLE_NAMES[kind], 'Existing custom role has an unexpected name');
  assert.notEqual(role.deleted, true, 'Existing role is deleted; review before reuse');
  assert.notEqual(role.stage, 'DISABLED', 'Existing role is disabled; review before reuse');
  assert.deepEqual([...(role.includedPermissions || [])].sort(), [...PERMISSIONS[kind]].sort(),
    'Existing role permissions differ; refusing to alter it');
}

function validateAccount(account) {
  if (!account) return;
  assert.equal(account.email, SERVICE_ACCOUNT);
  assert.equal(account.projectId, PROJECT);
  assert.notEqual(account.disabled, true, 'Existing broker service account is disabled');
}

function assertProjectGrants(policy) {
  for (const binding of policy.bindings || []) {
    if ((binding.members || []).includes(MEMBER)) {
      assert.equal(binding.role, ROLE_NAMES.auth,
        'Broker already has an unexpected project-wide role; review instead of adding access');
    }
  }
}

function hasBinding(policy, role) {
  return (policy?.bindings || []).some(b => b.role === role && !b.condition && (b.members || []).includes(MEMBER));
}

function addBinding(policy, role) {
  assert(policy && typeof policy.etag === 'string' && policy.etag, 'IAM etag required; refusing blind policy replacement');
  const next = structuredClone(policy);
  if (hasBinding(next, role)) return {policy: next, changed: false};
  next.bindings ||= [];
  let binding = next.bindings.find(b => b.role === role && !b.condition);
  if (!binding) { binding = {role, members: []}; next.bindings.push(binding); }
  binding.members.push(MEMBER);
  return {policy: next, changed: true};
}

async function optionalGet(api, resource) {
  try { return (await api.get(resource)).body; }
  catch (error) { if (error.status === 404) return null; throw error; }
}

function clients(session) {
  return {
    iam: session.api('iam.googleapis.com', 'v1'),
    crm: session.api('cloudresourcemanager.googleapis.com', 'v1'),
    services: session.api('serviceusage.googleapis.com', 'v1'),
  };
}

async function projectPolicy(crm) {
  const policy = (await crm.post(`/projects/${PROJECT}:getIamPolicy`, {options: {requestedPolicyVersion: 3}})).body;
  assertProjectGrants(policy);
  return policy;
}

async function accountPolicy(iam) {
  return (await iam.post(`${ACCOUNT_RESOURCE}:getIamPolicy`, {options: {requestedPolicyVersion: 3}})).body;
}

async function inspect(api) {
  const account = await optionalGet(api.iam, ACCOUNT_RESOURCE); validateAccount(account);
  const authRole = await optionalGet(api.iam, '/' + ROLE_NAMES.auth); validateRole(authRole, 'auth');
  const signRole = await optionalGet(api.iam, '/' + ROLE_NAMES.sign); validateRole(signRole, 'sign');
  const project = await projectPolicy(api.crm);
  const own = account ? await accountPolicy(api.iam) : null;
  const signingApi = (await api.services.get(`/projects/${NUMBER}/services/iamcredentials.googleapis.com`)).body;
  const readiness = {
    serviceAccount: Boolean(account), authReadRole: Boolean(authRole), selfSignRole: Boolean(signRole),
    projectReadGrant: hasBinding(project, ROLE_NAMES.auth),
    selfSigningGrant: hasBinding(own, ROLE_NAMES.sign),
    iamCredentialsApi: signingApi.state === 'ENABLED',
  };
  return {account, project, own, authRole, signRole, readiness, ready: Object.values(readiness).every(Boolean)};
}

async function applySetup(session, api, initial) {
  const changes = [];
  if (!initial.account) {
    const result = (await api.iam.post(`/projects/${PROJECT}/serviceAccounts`, {
      accountId: ACCOUNT_ID,
      serviceAccount: {displayName: 'MYDOXXX cloud lab token broker', description: 'Owner-gated existing synthetic-role token broker only'},
    })).body;
    validateAccount(result); changes.push('created_dedicated_service_account');
  }
  for (const kind of ['auth', 'sign']) {
    // Re-read immediately before create. A concurrent incompatible role stops us.
    const current = await optionalGet(api.iam, '/' + ROLE_NAMES[kind]); validateRole(current, kind);
    if (!current) {
      const result = (await api.iam.post(`/projects/${PROJECT}/roles`, {roleId: ROLE_IDS[kind], role: roleDefinition(kind)})).body;
      validateRole(result, kind); changes.push(`created_${kind}_custom_role`);
    }
  }
  if (!initial.readiness.iamCredentialsApi) {
    await session.ensure(['iamcredentials.googleapis.com']); changes.push('enabled_iam_credentials_api');
  }
  // Preserve the freshly read full policies, etags, conditional bindings and
  // auditConfigs. An IAM conflict is surfaced, never retried with a blind write.
  const project = addBinding(await projectPolicy(api.crm), ROLE_NAMES.auth);
  if (project.changed) {
    await api.crm.post(`/projects/${PROJECT}:setIamPolicy`, {policy: project.policy});
    changes.push('granted_project_auth_read_to_broker_only');
  }
  const own = addBinding(await accountPolicy(api.iam), ROLE_NAMES.sign);
  if (own.changed) {
    await api.iam.post(`${ACCOUNT_RESOURCE}:setIamPolicy`, {policy: own.policy});
    changes.push('granted_sign_blob_on_broker_account_to_itself_only');
  }
  return changes;
}

async function main(argv = process.argv.slice(2)) {
  assert(argv.length <= 1 && (!argv.length || ['--check', '--apply'].includes(argv[0])), 'Use --check (default) or explicit --apply only');
  const apply = argv[0] === '--apply';
  const common = loadCommon();
  const session = await common.session();
  const api = clients(session);
  const before = await inspect(api);
  const changes = apply ? await applySetup(session, api, before) : [];
  const after = apply ? await inspect(api) : before;
  const report = {
    projectId: PROJECT, projectNumber: NUMBER, serviceAccount: SERVICE_ACCOUNT,
    mode: apply ? 'APPLY' : 'READ_ONLY', mutationsRequested: apply, changes,
    readiness: after.readiness, ready: after.ready,
    authReadRole: ROLE_NAMES.auth, selfSignRole: ROLE_NAMES.sign,
    signingBindingScope: ACCOUNT_RESOURCE, runtimeUserWrites: false, firestoreAccessGranted: false,
    checkedAt: new Date().toISOString(),
  };
  if (apply) {
    await common.save('cloud-test-room-broker-iam-setup.json', report);
    assert(after.ready, 'Setup has not fully propagated; rerun --check, do not broaden access');
  }
  console.log(JSON.stringify(report, null, 2));
}

module.exports = {PROJECT, NUMBER, OWNER, MEMBER, ACCOUNT_RESOURCE, ROLE_NAMES, PERMISSIONS,
  roleDefinition, validateRole, validateAccount, assertProjectGrants, hasBinding, addBinding,
  inspect, applySetup, main};
if (require.main === module) main().catch(error => {
  // Common SDK errors may carry response bodies; do not dump them or auth state.
  const safe = error instanceof assert.AssertionError ? error.message : 'Operation failed; inspect access/API status without exposing credentials';
  console.error('Broker IAM setup stopped: ' + safe);
  process.exitCode = 2;
});
