'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {validateRun, main} = require('./validate-preview.cjs');
const env = () => ({PREVIEW_RUN_ID:'12345', PLAN_SHA256:'a'.repeat(64), GITHUB_SHA:'b'.repeat(40), GITHUB_RUN_ID:'67890'});
const valid = () => ({id:12345, path:'.github/workflows/mydoxxx-data.yml', event:'workflow_dispatch',
  head_branch:'main', head_sha:'b'.repeat(40), head_repository:{id:1442833578, full_name:'shrinath4all-del/MYDOXXX'},
  actor:{id:281172251}, triggering_actor:{id:281172251}, display_title:'MYDOXXX data / preview',
  status:'completed', conclusion:'success', run_attempt:1});

test('only successful owner preview of this exact main commit is accepted', () => {
  assert.deepEqual(validateRun(valid(),env()), {runAttempt:1});
});
test('GitHub canonical workflow path may include only the trusted main ref', () => {
  const workflow = '.github/workflows/mydoxxx-data.yml';
  for(const path of [workflow, workflow + '@main', workflow + '@refs/heads/main'])
    assert.deepEqual(validateRun({...valid(),path},env()), {runAttempt:1});
  for(const path of [workflow + '@other', workflow + '@refs/heads/other', workflow + '@refs/tags/main', workflow + '@main/other'])
    assert.throws(() => validateRun({...valid(),path},env()));
});
test('preview provenance rejects cross-repository, untrusted actor, rerun and changed commit', () => {
  const bad = [
    {id:67890}, {path:'.github/workflows/other.yml'}, {event:'pull_request'},
    {head_branch:'task'}, {head_sha:'c'.repeat(40)}, {head_repository:{id:99,full_name:'shrinath4all-del/MYDOXXX'}},
    {head_repository:{id:1442833578,full_name:'other/MYDOXXX'}}, {repository:{id:99,full_name:'other/MYDOXXX'}},
    {actor:{id:99}}, {triggering_actor:{id:99}}, {display_title:'MYDOXXX data / apply'},
    {status:'in_progress'}, {conclusion:'failure'}, {run_attempt:2}, {run_attempt:undefined},
  ];
  for(const patch of bad) assert.throws(() => validateRun({...valid(),...patch},env()), JSON.stringify(patch));
});
test('untrusted preview ID or plan hash cannot be interpolated into a request', () => {
  for(const id of ['../1','123/../../x','1?x=y','0','1\n2','']) assert.throws(() => validateRun(valid(),{...env(),PREVIEW_RUN_ID:id}));
  for(const hash of ['a'.repeat(63),'A'.repeat(64),'a'.repeat(64)+'\n','']) assert.throws(() => validateRun(valid(),{...env(),PLAN_SHA256:hash}));
});
test('the current run cannot approve itself', () => {
  assert.throws(() => validateRun(valid(), {...env(),GITHUB_RUN_ID:'12345'}));
});
test('invalid runner context cannot make a GitHub network request', async () => {
  let calls = 0;
  const fetchImpl = async () => {calls++; throw new Error('Must not fetch');};
  await assert.rejects(main({},fetchImpl));
  assert.equal(calls,0);
});
const runner = () => ({...env(), GITHUB_REPOSITORY:'shrinath4all-del/MYDOXXX', GITHUB_REPOSITORY_ID:'1442833578',
  GITHUB_ACTOR_ID:'281172251', GITHUB_TRIGGERING_ACTOR:'shrinath4all-del', GITHUB_REF:'refs/heads/main',
  GITHUB_EVENT_NAME:'workflow_dispatch', GITHUB_RUN_ATTEMPT:'1', RUNNER_ENVIRONMENT:'github-hosted',
  OPERATION:'apply', GITHUB_TOKEN:'synthetic-github-token-for-offline-test', GITHUB_OUTPUT:'unused'});
test('rerun and self-hosted context fail before fetching the artifact provenance', async () => {
  let calls = 0;
  const fetchImpl = async () => {calls++; throw new Error('Must not fetch');};
  for(const override of [{GITHUB_RUN_ATTEMPT:'2'},{RUNNER_ENVIRONMENT:'self-hosted'},
    {GITHUB_TRIGGERING_ACTOR:'someone-else'}, {GITHUB_REF:'refs/heads/feature'}])
    await assert.rejects(main({...runner(),...override},fetchImpl));
  assert.equal(calls,0);
});
test('verified metadata exports only the attempt and keeps token out of output', async () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(),'mydox-preview-test-'));
  const output = path.join(folder,'output');
  try {
    let calls = 0;
    await main({...runner(),GITHUB_OUTPUT:output},async (url,options) => {
      calls++;
      assert.equal(url,'https://api.github.com/repos/shrinath4all-del/MYDOXXX/actions/runs/12345');
      assert.equal(options.redirect,'error');
      assert.equal(options.headers.Authorization,'Bearer synthetic-github-token-for-offline-test');
      return {ok:true,json:async () => valid()};
    });
    assert.equal(calls,1);
    assert.equal(fs.readFileSync(output,'utf8'),'run_attempt=1\n');
  } finally {
    // Only the uniquely created test directory and fixed file above are removed.
    if(fs.existsSync(output)) fs.unlinkSync(output);
    fs.rmdirSync(folder);
  }
});

const root = path.resolve(__dirname,'../../..');
const wf = fs.readFileSync(path.join(root,'.github/workflows/mydoxxx-data.yml'),'utf8');
const checks = fs.readFileSync(path.join(root,'.github/workflows/mydoxxx-data-checks.yml'),'utf8');
test('database workflow cannot run automatically on a push or a pull request', () => {
  const triggers = wf.slice(wf.indexOf('\non:'),wf.indexOf('\npermissions:'));
  assert.match(triggers,/\n  workflow_dispatch:/);
  assert.doesNotMatch(triggers,/\n  (push|pull_request|pull_request_target|schedule|workflow_run|repository_dispatch|workflow_call):/);
  assert.match(wf,/github\.ref == 'refs\/heads\/main'/);
  assert.match(wf,/github\.repository_id == '1442833578'/);
  assert.match(wf,/github\.actor_id == '281172251'/);
  assert.match(wf,/github\.run_attempt == '1'/);
  assert.match(wf,/github\.triggering_actor == 'shrinath4all-del'/);
  assert.match(wf,/cancel-in-progress: false/);
});
test('cloud workflow uses immutable action pins and exact plan/report artifact paths', () => {
  for(const line of [...wf.split('\n'),...checks.split('\n')].filter(l => /uses:/.test(l)))
    assert.match(line,/uses: actions\/[a-z-]+@[a-f0-9]{40}(?: #|$)/);
  assert.match(wf,/ref: \$\{\{ github.sha \}\}/);
  assert.match(wf,/path: cloud-data-output\/plan.json/);
  assert.match(wf,/path: cloud-data-output\/report.json/);
  assert.doesNotMatch(wf,/path: ["']?(\.|\*|private-backups|gha-creds)/);
  assert(wf.indexOf('validate-preview.cjs') < wf.indexOf('uses: actions/download-artifact@'));
  assert(wf.indexOf('uses: actions/download-artifact@') < wf.indexOf('run: node scripts/mydoxxx/cloud-data/run.cjs'));
});
test('PR checks have no OIDC or mutation step; neither workflow requests repository write access', () => {
  assert.doesNotMatch(checks,/id-token:|run\.cjs|validate-preview\.cjs|secrets\./);
  for(const content of [wf,checks]) {
    assert.doesNotMatch(content,/(contents|actions|pull-requests|deployments): write|secrets\.|pull_request_target:/);
    assert.doesNotMatch(content,/firebase (deploy|login)|netlify deploy|GOOGLE_APPLICATION_CREDENTIALS/);
  }
});
