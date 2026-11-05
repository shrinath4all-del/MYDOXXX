'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const bash = process.platform === 'win32'
  ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'Git', 'bin', 'bash.exe')
  : 'bash';
const script = path.join(__dirname, 'ci-build.sh').replace(/\\/g, '/');
const approved = {
  NETLIFY: 'true',
  CONTEXT: 'production',
  BRANCH: 'main',
  URL: 'https://mydoxxx-live-test.netlify.app',
  REPOSITORY_URL: 'git@github.com:shrinath4all-del/MYDOXXX',
};

function validate(overrides = {}) {
  // Run the real guard's early-exit mode: no downloads, builds or deployments.
  const result = spawnSync(bash, ['--noprofile', '--norc', script, '--validate-context'], {
    env: { ...process.env, ...approved, ...overrides },
    encoding: 'utf8',
    timeout: 10_000,
    windowsHide: true,
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null, 'context check must terminate normally');
  return result;
}

for (const repository of [
  'https://github.com/shrinath4all-del/MYDOXXX',
  'https://github.com/shrinath4all-del/MYDOXXX.git',
  'git@github.com:shrinath4all-del/MYDOXXX',
  'git@github.com:shrinath4all-del/MYDOXXX.git',
]) {
  test(`approved repository URL: ${repository}`, () => {
    const result = validate({ REPOSITORY_URL: repository });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Approved context: main -> https:\/\/mydoxxx-live-test\.netlify\.app/);
    assert.match(result.stdout, /no build\/deployment performed/);
  });
}

for (const repository of [
  '',
  'https://github.com/another-owner/MYDOXXX',
  'git@github.com:shrinath4all-del/another-repository',
  'git@github.com:shrinath4all-del/MYDOXXX-extra',
  'git@github.com:shrinath4all-del/MYDOXXX.git/extra',
  'git@github.com:shrinath4all-del/MYDOXXX.git?ref=main',
  'https://github.com/shrinath4all-del/MYDOXXX#main',
  'https://github.com.evil.example/shrinath4all-del/MYDOXXX',
  'https://github.com@evil.example/shrinath4all-del/MYDOXXX',
  'git@github.com:shrinath4all-del/MYDOXXX ',
]) {
  test(`unapproved repository URL is rejected: ${JSON.stringify(repository)}`, () => {
    const result = validate({ REPOSITORY_URL: repository });
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stderr, /Unexpected source repository/);
    assert.doesNotMatch(result.stdout, /Approved context/);
  });
}

for (const [name, overrides, message] of [
  ['missing native environment', { NETLIFY: '' }, /Expected the native Netlify build environment/],
  ['deploy preview', { CONTEXT: 'deploy-preview' }, /Only production deploy context is approved/],
  ['branch deploy', { CONTEXT: 'branch-deploy' }, /Only production deploy context is approved/],
  ['feature branch', { BRANCH: 'codex/another-task' }, /Only reviewed main is the production branch/],
  ['unrelated site', { URL: 'https://mydoxxxx.netlify.app' }, /approved MYDOXXX cloud site/],
  ['lookalike site', { URL: 'https://mydoxxx-live-test.netlify.app.evil.example' }, /approved MYDOXXX cloud site/],
]) {
  test(`approved repository cannot bypass ${name}`, () => {
    const result = validate(overrides);
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stderr, message);
    assert.doesNotMatch(result.stdout, /Approved context/);
  });
}
