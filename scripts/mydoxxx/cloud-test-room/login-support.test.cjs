const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const path=require('node:path'),{pathToFileURL}=require('node:url'),vm=require('node:vm');
const load=()=>import(pathToFileURL(path.join(__dirname,'login-support.js')).href);

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
 for(const bad of [undefined,null,'oops',42,{},{code:42},{code:'__proto__'},{code:'constructor'},{code:'toString'},{code:'auth/new-code',message:'secret-like-detail eyJhbGciOi'},new Error('raw internal message')])
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
 const identity=fs.readFileSync(__dirname+'/owner-identity.js','utf8');
 assert.match(identity,/emailVerified/);assert.match(identity,/google\.com/);
 assert.match(auth,/matchesOwner\(user,config\.ownerEmailSha256\)/);
 assert.match(auth,/await approved\(user\)/);
});

// Execute the actual login.js DOM/controller code with a fake Auth boundary and
// controllable timers. No Google/Firebase/network or real browser sign-in occurs.
async function bootLogin({storageBlocked=false,approval=async user=>user?.approved===true}={}){
 const support=await load(),button={disabled:true,textContent:''},status={textContent:''};
 const attempts=[],timers=[],navigation=[];let signOuts=0,reloads=0;
 const auth={ready:Promise.resolve(null),storageBlocked,approved:approval,
  login:()=>new Promise((resolve,reject)=>attempts.push({resolve,reject})),
  logout:async()=>{signOuts++;}};
 const context={document:{getElementById:id=>id==='signin'?button:status},
  location:{assign:url=>navigation.push(url),replace:url=>navigation.push(url),reload:()=>reloads++},
  __loadOwner:async()=>auth,
  __loadSupport:async()=>({...support,watchSlow:(ms,fn)=>{const timer={ms,fn,cancelled:false};timers.push(timer);return()=>{timer.cancelled=true;};}})};
 let source=fs.readFileSync(path.join(__dirname,'login.js'),'utf8');
 for(const [from,to] of [["await import('./owner-auth.js')","await __loadOwner()"],["await import('./login-support.js')","await __loadSupport()"]]){
  assert.equal(source.split(from).length-1,1,'Expected reviewed import boundary');source=source.replace(from,to);
 }
 await vm.runInNewContext('(async()=>{'+source+'\n})()',context);
 return {button,status,attempts,timers,navigation,signOuts:()=>signOuts,reloads:()=>reloads};
}

test('retry keeps its UI when an earlier popup rejects or an earlier watchdog runs',async()=>{
 const ui=await bootLogin(),first=ui.button.onclick();
 assert.equal(ui.button.disabled,true);ui.timers[0].fn();
 assert.match(ui.status.textContent,/still waiting for a result/);
 assert.doesNotMatch(ui.status.textContent,/No Google sign-in window was detected/);
 assert.equal(ui.button.disabled,false);
 const second=ui.button.onclick();assert.equal(ui.button.disabled,true);assert.equal(ui.status.textContent,'');
 ui.attempts[0].reject({code:'auth/cancelled-popup-request'});await first;
 ui.timers[0].fn();assert.equal(ui.status.textContent,'');assert.equal(ui.button.disabled,true);
 ui.attempts[1].resolve({user:{approved:true}});await second;
 assert.deepEqual(ui.navigation,['/room.html']);assert.ok(ui.timers.every(t=>t.cancelled));
});

test('stale popup success cannot navigate or sign out the current attempt',async()=>{
 const ui=await bootLogin(),first=ui.button.onclick();ui.timers[0].fn();const second=ui.button.onclick();
 ui.attempts[0].resolve({user:{approved:false}});await first;
 assert.equal(ui.signOuts(),0);assert.deepEqual(ui.navigation,[]);assert.equal(ui.button.disabled,true);
 ui.attempts[1].resolve({user:{approved:true}});await second;
 assert.deepEqual(ui.navigation,['/room.html']);
});

test('current wrong account signs out; blocked storage offers only a reload',async()=>{
 const ui=await bootLogin(),attempt=ui.button.onclick();
 ui.attempts[0].resolve({user:{approved:false}});await attempt;
 assert.equal(ui.signOuts(),1);assert.deepEqual(ui.navigation,[]);
 assert.match(ui.status.textContent,/Please use the authorised Google account/);
 assert.doesNotMatch(ui.status.textContent,/@/);
 const blocked=await bootLogin({storageBlocked:true});
 assert.match(blocked.status.textContent,/blocking the temporary storage/);
 assert.equal(blocked.button.textContent,'Reload this page');blocked.button.onclick();
 assert.equal(blocked.reloads(),1);assert.equal(blocked.attempts.length,0);
});

test('an older delayed identity check cannot sign out a newer attempt',async()=>{
 let resolveCheck;const identityCheck=new Promise(resolve=>{resolveCheck=resolve;});
 const ui=await bootLogin({approval:user=>!user?Promise.resolve(false):user.delay?identityCheck:Promise.resolve(user.approved===true)});
 const first=ui.button.onclick();ui.attempts[0].resolve({user:{delay:true}});await new Promise(setImmediate);
 ui.timers[0].fn();const second=ui.button.onclick();
 resolveCheck(false);await first;assert.equal(ui.signOuts(),0);assert.deepEqual(ui.navigation,[]);
 ui.attempts[1].resolve({user:{approved:true}});await second;assert.deepEqual(ui.navigation,['/room.html']);
});

