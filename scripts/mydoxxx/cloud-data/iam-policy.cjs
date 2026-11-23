'use strict';
// Public, destination-specific IAM contract. Importing it has no side effects.
// This creates no service account or reusable key. Actual setup is owner-run.
const PROJECT = 'mydoxxx-dev-261102';
const PROJECT_NUMBER = '724915428929';
const DATABASE = 'mydoxxx-testing';
const DATABASE_RESOURCE = `projects/${PROJECT}/databases/${DATABASE}`;
const REPOSITORY = 'shrinath4all-del/MYDOXXX';
const REPOSITORY_ID = '1442833578';
const OWNER_ID = '281172251';
const POOL_ID = 'mydoxxx-github-data';
const PROVIDER_ID = 'github';
const POOL_RESOURCE = `projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}`;
const PROVIDER_RESOURCE = `${POOL_RESOURCE}/providers/${PROVIDER_ID}`;
const OIDC_AUDIENCE = `https://iam.googleapis.com/${PROVIDER_RESOURCE}`;
const STS_AUDIENCE = `//iam.googleapis.com/${PROVIDER_RESOURCE}`;
const ROLE_ID = 'mydoxxxCloudData';
const ROLE_NAME = `projects/${PROJECT}/roles/${ROLE_ID}`;
const MEMBER = `principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository_id/${REPOSITORY_ID}`;
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/mydoxxx-data.yml@refs/heads/main`;

// Use the GitHub-signed immutable IDs as well as the readable name/ref.
// run_attempt=1 prevents another writer from rerunning an owner's old run,
// whose actor_id still identifies its original initiator. Retry with a new run.
const REQUIRED_CLAIMS = Object.freeze({
  repository_id: REPOSITORY_ID,
  repository_owner_id: OWNER_ID,
  actor_id: OWNER_ID,
  repository: REPOSITORY,
  ref: 'refs/heads/main',
  event_name: 'workflow_dispatch',
  workflow_ref: WORKFLOW_REF,
  run_attempt: '1',
  runner_environment: 'github-hosted',
});
const ATTRIBUTE_CONDITION = Object.entries(REQUIRED_CLAIMS)
  .map(([name, value]) => `assertion.${name} == '${value}'`).join(' && ');
const DATABASE_CONDITION = `resource.name == "${DATABASE_RESOURCE}"`;

const POOL = Object.freeze({
  displayName: 'MYDOXXX GitHub data',
  description: 'Owner-triggered cloud jobs for the MYDOXXX synthetic database only.',
  disabled: false,
});
const PROVIDER = Object.freeze({
  displayName: 'Owner GitHub workflow',
  description: 'Exact repository, owner, main workflow and first manual run only.',
  disabled: false,
  attributeMapping: Object.freeze({
    'google.subject': 'assertion.sub',
    'attribute.repository_id': 'assertion.repository_id',
    'attribute.repository_owner_id': 'assertion.repository_owner_id',
    'attribute.actor_id': 'assertion.actor_id',
  }),
  attributeCondition: ATTRIBUTE_CONDITION,
  oidc: Object.freeze({
    issuerUri: 'https://token.actions.githubusercontent.com',
    allowedAudiences: Object.freeze([OIDC_AUDIENCE]),
  }),
});
const ROLE = Object.freeze({
  title: 'MYDOXXX synthetic data updater',
  description: 'Read database metadata and read/create/update synthetic documents. No delete or administration.',
  stage: 'GA',
  includedPermissions: Object.freeze([
    'datastore.databases.getMetadata',
    'datastore.entities.get',
    'datastore.entities.list',
    'datastore.entities.create',
    'datastore.entities.update',
  ]),
});
const BINDING = Object.freeze({
  role: ROLE_NAME,
  members: Object.freeze([MEMBER]),
  condition: Object.freeze({
    title: 'MYDOXXX_named_test_database_only',
    description: 'No access to the restored default database or any other database.',
    expression: DATABASE_CONDITION,
  }),
});

// A test helper, not a JWT verifier. Google validates the signature, issuer,
// audience and the CEL provider condition. Never trust an unsigned JWT locally.
function matchesTrustClaims(claims) {
  return !!claims && Object.entries(REQUIRED_CLAIMS)
    .every(([key, value]) => claims[key] === value);
}

module.exports = {
  PROJECT, PROJECT_NUMBER, DATABASE, DATABASE_RESOURCE, REPOSITORY,
  REPOSITORY_ID, OWNER_ID, POOL_ID, PROVIDER_ID, POOL_RESOURCE,
  PROVIDER_RESOURCE, OIDC_AUDIENCE, STS_AUDIENCE, ROLE_ID, ROLE_NAME,
  MEMBER, WORKFLOW_REF, REQUIRED_CLAIMS, ATTRIBUTE_CONDITION,
  DATABASE_CONDITION, POOL, PROVIDER, ROLE, BINDING, matchesTrustClaims,
};
