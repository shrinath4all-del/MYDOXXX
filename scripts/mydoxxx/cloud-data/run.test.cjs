'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {exchange,PROVIDER,AUDIENCE}=require('./run.cjs');
const env={ACTIONS_ID_TOKEN_REQUEST_TOKEN:'synthetic-github-secret',ACTIONS_ID_TOKEN_REQUEST_URL:'https://pipelines.actions.githubusercontent.com/token?api-version=2'};
const response=value=>({ok:true,json:async()=>value});
test('exchanges a GitHub JWT directly with Google using fixed audience and datastore scope',async()=>{
 const calls=[];
 const token=await exchange(env,async(url,options)=>{calls.push({url:String(url),options});return calls.length===1?response({value:'header.claims.signature'}):response({access_token:'synthetic-google-token-12345',token_type:'Bearer',expires_in:300});});
 assert.equal(token,'synthetic-google-token-12345');
 assert.equal(new URL(calls[0].url).searchParams.get('audience'),AUDIENCE);
 assert.equal(calls[1].url,'https://sts.googleapis.com/v1/token');
 assert.equal(calls[1].options.body.get('audience'),'//iam.googleapis.com/'+PROVIDER);
 assert.equal(calls[1].options.body.get('scope'),'https://www.googleapis.com/auth/datastore');
 assert.equal(calls[1].options.body.get('subject_token'),'header.claims.signature');
 assert.equal(calls[1].options.headers.Authorization,undefined);
 assert.equal(calls[1].options.redirect,'error');
});
test('refuses insecure or unrelated identity endpoints before any network call',async()=>{
 for(const url of ['http://pipelines.actions.githubusercontent.com/token','https://example.com/token','https://pipelines.actions.githubusercontent.com.evil.test/token','https://user:pass@pipelines.actions.githubusercontent.com/token']){
  let calls=0;await assert.rejects(exchange({...env,ACTIONS_ID_TOKEN_REQUEST_URL:url},async()=>{calls++;}));assert.equal(calls,0);
 }
});
test('does not continue when GitHub denies token issuance',async()=>{
 let calls=0;await assert.rejects(exchange(env,async()=>{calls++;return{ok:false};}),/GitHub OIDC request failed/);assert.equal(calls,1);
});
test('rejects a missing JWT without contacting Google',async()=>{
 let calls=0;await assert.rejects(exchange(env,async()=>{calls++;return response({value:'not-jwt'});}));assert.equal(calls,1);
});
test('Google denial is sanitized and never returns response body secrets',async()=>{
 let calls=0;await assert.rejects(exchange(env,async()=>++calls===1?response({value:'h.c.s'}):{ok:false,json:async()=>{throw Error('must not read secret error body');}}),/Google rejected/);
});
test('rejects short-lived or malformed Google credentials',async()=>{
 for(const value of [{access_token:'synthetic-token-long-enough',token_type:'Bearer',expires_in:1},{access_token:'tiny',token_type:'Bearer',expires_in:300},{access_token:'synthetic-token-long-enough',token_type:'unknown',expires_in:300}]){
  let calls=0;await assert.rejects(exchange(env,async()=>++calls===1?response({value:'h.c.s'}):response(value)));
 }
});
