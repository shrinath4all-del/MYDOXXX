'use strict';
// GitHub provenance checks, before any plan is downloaded or Google token obtained.
// This does not execute scripts from the preview artifact; only plan.json is used.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const REPO = 'shrinath4all-del/MYDOXXX';
const REPO_ID = 1442833578;
const OWNER_ID = 281172251;
const WORKFLOW = '.github/workflows/mydoxxx-data.yml';

function validateRun(run, env) {
  assert.match(env.PREVIEW_RUN_ID || '', /^[1-9][0-9]{0,19}$/, 'A numeric preview run ID is required');
  assert.match(env.PLAN_SHA256 || '', /^[a-f0-9]{64}$/, 'The exact preview SHA-256 is required');
  assert.equal(String(run.id), env.PREVIEW_RUN_ID, 'Wrong preview run');
  assert([WORKFLOW, WORKFLOW + '@main', WORKFLOW + '@refs/heads/main'].includes(run.path), 'Preview used another workflow or branch');
  assert.equal(run.event, 'workflow_dispatch', 'Preview was not manually requested');
  assert.equal(run.head_branch, 'main', 'Preview was not on main');
  assert.equal(run.head_sha, env.GITHUB_SHA, 'Main changed; run a new preview before applying');
  assert.equal(run.head_repository?.id, REPO_ID, 'Preview belongs to another repository');
  assert.equal(run.head_repository?.full_name, REPO, 'Preview repository name changed');
  if (run.repository) {
    assert.equal(run.repository.id, REPO_ID, 'Wrong run repository');
    assert.equal(run.repository.full_name, REPO, 'Wrong run repository name');
  }
  assert.equal(run.actor?.id, OWNER_ID, 'Preview was not requested by the owner');
  assert.equal(run.triggering_actor?.id, OWNER_ID, 'Preview rerun was not requested by the owner');
  assert.equal(run.display_title, 'MYDOXXX data / preview', 'Only a preview run can be approved');
  assert.equal(run.status, 'completed', 'Wait for the preview to finish');
  assert.equal(run.conclusion, 'success', 'The preview did not pass');
  assert.equal(run.run_attempt, 1, 'Reruns are not eligible; request a fresh owner preview');
  assert.notEqual(String(run.id), env.GITHUB_RUN_ID, 'Cannot approve the current run');
  return {runAttempt: run.run_attempt};
}

async function main(env = process.env, fetchImpl = fetch) {
  assert.equal(env.GITHUB_REPOSITORY, REPO);
  assert.equal(env.GITHUB_REPOSITORY_ID, String(REPO_ID));
  assert.equal(env.GITHUB_ACTOR_ID, String(OWNER_ID));
  assert.equal(env.GITHUB_TRIGGERING_ACTOR, 'shrinath4all-del');
  assert.equal(env.GITHUB_REF, 'refs/heads/main');
  assert.equal(env.GITHUB_EVENT_NAME, 'workflow_dispatch');
  assert.equal(env.GITHUB_RUN_ATTEMPT, '1');
  assert.equal(env.RUNNER_ENVIRONMENT, 'github-hosted');
  assert.equal(env.OPERATION, 'apply');
  assert.match(env.PREVIEW_RUN_ID || '', /^[1-9][0-9]{0,19}$/);
  assert.match(env.PLAN_SHA256 || '', /^[a-f0-9]{64}$/);
  assert(env.GITHUB_TOKEN && env.GITHUB_OUTPUT, 'GitHub runner context required');
  const response = await fetchImpl(`https://api.github.com/repos/${REPO}/actions/runs/${env.PREVIEW_RUN_ID}`, {
    headers: {Authorization: `Bearer ${env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
    redirect: 'error', signal: AbortSignal.timeout(15000),
  });
  assert(response.ok, 'Could not verify the preview run; no database request made');
  const result = validateRun(await response.json(), env);
  await fs.appendFile(env.GITHUB_OUTPUT, `run_attempt=${result.runAttempt}\n`);
  console.log('Preview provenance verified; only its plan artifact will be downloaded.');
}

if (require.main === module) main().catch(() => {
  console.error('Preview provenance check failed. Use a successful owner-requested preview from the same main commit.');
  process.exitCode = 1;
});
module.exports = {validateRun, main};
