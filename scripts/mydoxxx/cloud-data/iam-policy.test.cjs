'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const P = require('./iam-policy.cjs');

test('only the owner first-attempt manual main workflow matches trust', () => {
  assert.equal(P.matchesTrustClaims({...P.REQUIRED_CLAIMS, sub: 'repo:example'}), true);
  for (const key of Object.keys(P.REQUIRED_CLAIMS)) {
    const missing = {...P.REQUIRED_CLAIMS}; delete missing[key];
    assert.equal(P.matchesTrustClaims(missing), false, `${key} must be present`);
    assert.equal(P.matchesTrustClaims({...P.REQUIRED_CLAIMS, [key]: 'untrusted'}), false, `${key} must match`);
  }
  assert.equal(P.matchesTrustClaims(null), false);
});

test('trust rejects forks, replacement repositories, PRs, other workflows and reruns', () => {
  for (const patch of [
    {repository_id: '1442833579'}, {repository_owner_id: '288884259'},
    {actor_id: '288884259'}, {repository: 'other/MYDOXXX'},
    {ref: 'refs/pull/25/merge'}, {ref: 'refs/heads/codex/task'},
    {event_name: 'pull_request'}, {event_name: 'push'},
    {workflow_ref: P.WORKFLOW_REF.replace('mydoxxx-data.yml', 'mydox-cloud-checks.yml')},
    {workflow_ref: P.WORKFLOW_REF.replace('@refs/heads/main', '@refs/heads/other')},
    {run_attempt: '2'}, {run_attempt: 1}, {runner_environment: 'self-hosted'},
  ]) assert.equal(P.matchesTrustClaims({...P.REQUIRED_CLAIMS, ...patch}), false, JSON.stringify(patch));
});

test('Google condition and test matcher enforce the exact same claim values', () => {
  const clauses = P.ATTRIBUTE_CONDITION.split(' && ');
  assert.equal(clauses.length, Object.keys(P.REQUIRED_CLAIMS).length);
  for (const [key, value] of Object.entries(P.REQUIRED_CLAIMS)) {
    assert.ok(clauses.includes(`assertion.${key} == '${value}'`));
    assert.doesNotMatch(value, /['\\\n]/);
  }
  assert.doesNotMatch(P.ATTRIBUTE_CONDITION, /\|\||startsWith|endsWith/);
});

test('provider validates exact issuer and audience with numeric repository binding', () => {
  assert.equal(P.PROVIDER.oidc.issuerUri, 'https://token.actions.githubusercontent.com');
  assert.deepEqual(P.PROVIDER.oidc.allowedAudiences, [P.OIDC_AUDIENCE]);
  assert.equal(P.OIDC_AUDIENCE, `https://iam.googleapis.com/${P.PROVIDER_RESOURCE}`);
  assert.equal(P.STS_AUDIENCE, `//iam.googleapis.com/${P.PROVIDER_RESOURCE}`);
  assert.equal(P.PROVIDER.attributeMapping['attribute.repository_id'], 'assertion.repository_id');
  assert.equal(P.MEMBER, `principalSet://iam.googleapis.com/projects/724915428929/locations/global/workloadIdentityPools/mydoxxx-github-data/attribute.repository_id/1442833578`);
  assert.deepEqual(P.BINDING.members, [P.MEMBER]);
  assert.equal(P.PROVIDER.disabled, false);
});

test('custom role has only metadata and non-delete document permissions', () => {
  assert.deepEqual([...P.ROLE.includedPermissions].sort(), [
    'datastore.databases.getMetadata', 'datastore.entities.get',
    'datastore.entities.list', 'datastore.entities.create', 'datastore.entities.update',
  ].sort());
  assert.equal(P.BINDING.role, `projects/mydoxxx-dev-261102/roles/${P.ROLE_ID}`);
  assert.equal(P.ROLE.includedPermissions.some(x => /delete|admin|iam|storage|firebaseauth|functions|billing|\*/i.test(x)), false);
});

test('IAM condition limits access to the exact named test database', () => {
  assert.equal(P.BINDING.condition.expression, 'resource.name == "projects/mydoxxx-dev-261102/databases/mydoxxx-testing"');
  for (const db of ['(default)', 'mydoxxx-testing-other', 'production']) {
    assert.notEqual(`projects/${P.PROJECT}/databases/${db}`, P.DATABASE_RESOURCE);
  }
  for (const project of ['mydox-be432', 'clinigo-77808', 'mydox-shrinath-backup-261102', 'mydoxxx']) {
    assert.notEqual(`projects/${project}/databases/mydoxxx-testing`, P.DATABASE_RESOURCE);
  }
});
