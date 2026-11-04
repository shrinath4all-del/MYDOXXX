'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const setup = require('../setup-iam.cjs');

test('IAM addition preserves etag, conditions, other members and audit configuration', () => {
  const input = {version: 3, etag: 'stable-etag', bindings: [
    {role: 'roles/viewer', members: ['user:existing@example.com']},
    {role: setup.ROLE_NAMES.auth, members: ['user:reviewer@example.com'], condition: {title: 'temporary', expression: 'true'}},
  ], auditConfigs: [{service: 'allServices', auditLogConfigs: [{logType: 'ADMIN_READ'}]}]};
  const original = structuredClone(input);
  const {policy, changed} = setup.addBinding(input, setup.ROLE_NAMES.auth);
  assert.equal(changed, true); assert.deepEqual(input, original);
  assert.equal(policy.etag, input.etag); assert.equal(policy.version, 3);
  assert.deepEqual(policy.auditConfigs, input.auditConfigs);
  assert.deepEqual(policy.bindings.slice(0, 2), input.bindings);
  assert.deepEqual(policy.bindings[2], {role: setup.ROLE_NAMES.auth, members: [setup.MEMBER]});
  assert.equal(setup.addBinding(policy, setup.ROLE_NAMES.auth).changed, false);
});

test('IAM updates refuse missing etag and unexpected existing broker project roles', () => {
  assert.throws(() => setup.addBinding({bindings: []}, setup.ROLE_NAMES.auth));
  assert.throws(() => setup.assertProjectGrants({bindings: [{role: 'roles/editor', members: [setup.MEMBER]}]}));
  assert.throws(() => setup.assertProjectGrants({bindings: [{role: setup.ROLE_NAMES.sign, members: [setup.MEMBER]}]}));
  setup.assertProjectGrants({bindings: [{role: setup.ROLE_NAMES.auth, members: [setup.MEMBER]}]});
});

test('custom-role definitions allow only existing-user reads and self signBlob', () => {
  for (const kind of ['auth', 'sign']) {
    const def = setup.roleDefinition(kind);
    setup.validateRole({...def, name: setup.ROLE_NAMES[kind]}, kind);
    assert.throws(() => setup.validateRole({...def, name: setup.ROLE_NAMES[kind], includedPermissions: [...def.includedPermissions, 'firebaseauth.users.update']}, kind));
    assert.throws(() => setup.validateRole({...def, name: setup.ROLE_NAMES[kind], deleted: true}, kind));
  }
});

test('read-only inspect uses only gets and getIamPolicy POSTs, no enables/mutations', async () => {
  const calls = [];
  const client = {async get(resource) {
    calls.push(['get', resource]);
    if (resource.includes('/services/')) return {body: {state: 'DISABLED'}};
    const error = new Error('not found'); error.status = 404; throw error;
  }, async post(resource) {
    calls.push(['post', resource]); assert.match(resource, /:getIamPolicy$/);
    return {body: {etag: 'etag', bindings: []}};
  }};
  const result = await setup.inspect({iam: client, crm: client, services: client});
  assert.equal(result.ready, false);
  assert.equal(result.readiness.serviceAccount, false);
  assert.equal(calls.filter(c => c[0] === 'post').length, 1);
});
