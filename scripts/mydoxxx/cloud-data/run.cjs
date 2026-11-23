'use strict';
// Google access is minted for this one job and kept in memory. No key files.
const assert = require('node:assert/strict');
const PROVIDER = 'projects/724915428929/locations/global/workloadIdentityPools/mydoxxx-github-data/providers/github';
const AUDIENCE = 'https://iam.googleapis.com/' + PROVIDER;
async function exchange(env=process.env, request=fetch) {
  assert(env.ACTIONS_ID_TOKEN_REQUEST_TOKEN, 'GitHub OIDC is unavailable');
  const url = new URL(env.ACTIONS_ID_TOKEN_REQUEST_URL);
  assert.equal(url.protocol, 'https:');
  assert(url.hostname.endsWith('.actions.githubusercontent.com'), 'Unexpected GitHub token endpoint');
  assert(!url.username && !url.password, 'Unexpected token endpoint credentials');
  url.searchParams.set('audience', AUDIENCE);
  const oidcResponse = await request(url, {headers:{Authorization:'Bearer '+env.ACTIONS_ID_TOKEN_REQUEST_TOKEN}, signal:AbortSignal.timeout(30000), redirect:'error'});
  assert(oidcResponse.ok, 'GitHub OIDC request failed');
  const {value:jwt} = await oidcResponse.json();
  assert(typeof jwt === 'string' && jwt.split('.').length===3, 'GitHub returned no OIDC token');
  // Google verifies the signature, issuer, expiry, audience and provider claims.
  const response = await request('https://sts.googleapis.com/v1/token', {
    method:'POST', redirect:'error', signal:AbortSignal.timeout(30000),
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({
      audience:'//iam.googleapis.com/'+PROVIDER,
      grant_type:'urn:ietf:params:oauth:grant-type:token-exchange',
      requested_token_type:'urn:ietf:params:oauth:token-type:access_token',
      subject_token_type:'urn:ietf:params:oauth:token-type:jwt',
      scope:'https://www.googleapis.com/auth/datastore',subject_token:jwt
    })
  });
  assert(response.ok, 'Google rejected the workflow identity; check its trust policy');
  const token = await response.json();
  assert(token.token_type==='Bearer' && typeof token.access_token==='string' && token.access_token.length>20, 'Invalid Google token response');
  assert(Number.isFinite(token.expires_in) && token.expires_in>=30, 'Google token lifetime is too short');
  return token.access_token;
}
async function main() {
  const catalogue=require('./catalogue.cjs');
  catalogue.validateContext(process.env);
  assert(!process.env.GOOGLE_OAUTH_ACCESS_TOKEN, 'Do not supply a permanent or external token');
  const token=await exchange();
  await catalogue.main({env:{...process.env,GOOGLE_OAUTH_ACCESS_TOKEN:token}});
}
if(require.main===module) main().catch(()=>{console.error('Cloud data operation stopped. Review the named workflow step and its sanitized report. No token details are logged.');process.exitCode=1;});
module.exports={exchange,PROVIDER,AUDIENCE,main};
