const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'room-auth.js'),'utf8').replace(/^import .*;\r?\n/gm,'');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const origin='https://mydoxxx-live-test.netlify.app';
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};

async function setup(approved){
  const owner={uid:'fictional-owner',email:'fictional@example.test'},sent=[],redirects=[],listeners={};
  const frame={src:origin+'/panel/?role=patient',isConnected:true,contentWindow:{postMessage:(...args)=>sent.push(args)}};
  const auth={currentUser:owner},window={addEventListener:(name,fn)=>{listeners[name]=fn;}};
  const document={createElement:()=>({append(){}}),querySelectorAll:()=>[frame],
    body:{prepend(){},append:node=>node.onload()},documentElement:{classList:{remove(){}}}};
  await new AsyncFunction('config','auth','ready','approved','requestRole','logout','document','window','location','URL',source)(
    {origin},auth,Promise.resolve(owner),approved,async()=>({roleKey:'patient',customToken:'fake-test-grant'}),async()=>{},document,window,{replace:url=>redirects.push(url)},URL);
  return {auth,owner,sent,redirects,listeners,frame,event:{origin,source:frame.contentWindow,data:{type:'mydox:role-request',requestId:'test-request',roleKey:'patient'}}};
}

test('an asynchronous false owner check redirects without initializing private panels',async()=>{
  const s=await setup(async()=>false);
  assert.deepEqual(s.redirects,['/private.html']);assert.equal(s.listeners.message,undefined);assert.equal(s.sent.length,0);
});

test('role grant waits for asynchronous approval and never treats a Promise as approval',async()=>{
  const check=deferred();let calls=0;const s=await setup(()=>++calls===1?Promise.resolve(true):check.promise);
  const request=s.listeners.message(s.event);await new Promise(setImmediate);
  assert.equal(s.sent.length,0);check.resolve(false);await request;assert.equal(s.sent.length,0);
});

test('owner switch or frame replacement during approval prevents stale token delivery',async()=>{
  for(const change of [s=>{s.auth.currentUser={uid:'other-owner'};},s=>{s.frame.src=origin+'/panel/?role=doctor';},s=>{s.frame.isConnected=false;}]){
    const check=deferred();let calls=0;const s=await setup(()=>++calls===1?Promise.resolve(true):check.promise);
    const request=s.listeners.message(s.event);await new Promise(setImmediate);change(s);check.resolve(true);await request;
    assert.equal(s.sent.length,0);
  }
});

test('matching authorized frame receives one grant only after owner recheck',async()=>{
  const s=await setup(async()=>true);await s.listeners.message(s.event);
  assert.equal(s.sent.length,1);assert.equal(s.sent[0][0].type,'mydox:role-response');assert.equal(s.sent[0][1],origin);
});
