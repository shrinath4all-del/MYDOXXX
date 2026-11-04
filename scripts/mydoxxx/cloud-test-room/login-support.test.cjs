const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const load=()=>import(__dirname+'/login-support.js');

test('each known sign-in failure gets its own actionable message',async()=>{
 const {signInMessage,OPEN_IN_BROWSER,STORAGE_BLOCKED_MESSAGE}=await load();
 const text=code=>signInMessage({code});
 assert.match(text('auth/popup-blocked'),/Allow pop-ups/);
 assert.match(text('auth/popup-closed-by-user'),/cancelled/);
 assert.match(text('auth/cancelled-popup-request'),/cancelled/);
 assert.match(text('auth/network-request-failed'),/internet connection/);
 assert.match(text('auth/unauthorized-domain'),/mydoxxx-live-test\.netlify\.app/);
 assert.match(text('auth/operation-not-supported-in-this-environment'),/Chrome, Edge or Safari/);
 assert.equal(text('auth/web-storage-unsupported'),STORAGE_BLOCKED_MESSAGE);
 assert.ok(text('auth/operation-not-supported-in-this-environment').includes(OPEN_IN_BROWSER));
 const messages=new Set(['auth/popup-blocked','auth/network-request-failed','auth/unauthorized-domain','auth/too-many-requests','auth/user-disabled'].map(text));
 assert.equal(messages.size,5,'distinct failures must not share one generic message');
});

test('unknown or malformed errors never echo their own text',async()=>{
 const {signInMessage}=await load();
 const generic=signInMessage({});
 assert.match(generic,/could not complete/);
 for(const bad of [undefined,null,'oops',42,{},{code:42},{code:'auth/new-code',message:'secret-like-detail eyJhbGciOi'},new Error('raw internal message')])
  assert.equal(signInMessage(bad),generic);
});

test('only errors marked friendly may supply their own message',async()=>{
 const {signInMessage,friendlyError}=await load();
 assert.equal(signInMessage(friendlyError('Please use the authorised account.')),'Please use the authorised account.');
 assert.notEqual(signInMessage({userFacing:'yes',message:'spoof'}),'spoof');
 assert.notEqual(signInMessage({userFacing:true,message:42}),42);
});

test('slow-popup watchdog fires once after the delay and can be cancelled',async()=>{
 const {watchSlow}=await load();
 // Like a browser: calling these with a helper object as `this` is an error.
 const queue=[],timers={
  setTimeout:function(fn,ms){'use strict';if(this!==undefined)throw new TypeError('Illegal invocation');queue.push({fn,ms,live:true});return queue.length-1;},
  clearTimeout:function(id){'use strict';if(this!==undefined)throw new TypeError('Illegal invocation');queue[id].live=false;}};
 let calls=0;
 const stop=watchSlow(45000,()=>calls++,timers);
 assert.equal(queue[0].ms,45000);
 queue[0].fn();assert.equal(calls,1);
 stop();assert.equal(queue[0].live,false);
 let cancelled=0;const stop2=watchSlow(10,()=>cancelled++,timers);stop2();
 assert.equal(queue[1].live,false);assert.equal(cancelled,0);
});

test('the packager ships every module the login page imports',()=>{
 const packager=fs.readFileSync(__dirname+'/package-site.py','utf8');
 const login=fs.readFileSync(__dirname+'/login.js','utf8')+fs.readFileSync(__dirname+'/owner-auth.js','utf8');
 const imported=[...login.matchAll(/import\(?\s*(?:[^'"]*from\s*)?'\.\/([\w-]+\.js)'/g)].map(m=>m[1]);
 assert.ok(imported.includes('login-support.js')&&imported.includes('owner-auth.js')&&imported.includes('cloud-config.js'));
 for(const name of new Set(imported)) assert.ok(packager.includes("'"+name+"'"),name+' is imported but not packaged');
});

test('sign-in code never stores or logs tokens, and keeps the owner check',()=>{
 for(const file of ['login.js','owner-auth.js','login-support.js']){
  const code=fs.readFileSync(__dirname+'/'+file,'utf8');
  assert.doesNotMatch(code,/localStorage|console\.(log|info|debug)|getIdToken\([^)]*\)[^;]*(location|href)/,file);
 }
 const auth=fs.readFileSync(__dirname+'/owner-auth.js','utf8');
 assert.match(auth,/emailVerified/);assert.match(auth,/google\.com/);assert.match(auth,/config\.owner/);
});
