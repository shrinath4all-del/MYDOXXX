const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(__dirname+'/panel-bridge.js','utf8');
const origin='https://mydoxxx-live-test.netlify.app';
function boot(overrides={}){
 let handler;const sent=[],parent={postMessage:(data,target)=>sent.push({data,target})};
 const window={parent,addEventListener:(type,fn)=>{if(type==='message')handler=fn;}};
 const location={origin,pathname:'/panel/',href:origin+'/panel/?role=doctor_2&autologin=1',...overrides};
 vm.runInNewContext(source,{window,location,URL,crypto:{randomUUID:()=> 'request-one'},setTimeout,clearTimeout,Promise,Error,JSON,Map});
 return {window,parent,sent,reply:(data,from=parent,at=origin)=>handler({origin:at,source:from,data})};
}
test('bridge sends only role and request identity to exact parent origin',async()=>{
 const b=boot(),p=b.window.mydoxCloudTestLogin('doctor_2');
 assert.deepEqual(JSON.parse(JSON.stringify(b.sent)),[{data:{type:'mydox:role-request',requestId:'request-one',roleKey:'doctor_2'},target:origin}]);
 const result={roleKey:'doctor_2',customToken:'test-only-placeholder'};
 b.reply({type:'mydox:role-response',requestId:'request-one',result});
 assert.deepEqual(JSON.parse(await p),result);
});
test('bridge ignores wrong window, origin and request id',async()=>{
 const b=boot(),p=b.window.mydoxCloudTestLogin('doctor_2');let complete=false;p.then(()=>complete=true);
 const payload={type:'mydox:role-response',requestId:'request-one',result:{roleKey:'doctor_2',customToken:'placeholder'}};
 b.reply(payload,{});b.reply(payload,b.parent,'https://bad.example');b.reply({...payload,requestId:'wrong'});
 await Promise.resolve();assert.equal(complete,false);
 b.reply(payload);await p;assert.equal(complete,true);
});
test('bridge rejects other role and mismatched returned role',async()=>{
 const b=boot();await assert.rejects(b.window.mydoxCloudTestLogin('patient'));
 const p=b.window.mydoxCloudTestLogin('doctor_2');b.reply({type:'mydox:role-response',requestId:'request-one',result:{roleKey:'patient'}});await assert.rejects(p);
});
test('bridge rejects a denied grant and never initializes on another origin',async()=>{
 assert.equal(boot({origin:'https://bad.example'}).window.mydoxCloudTestLogin,undefined);
 const b=boot(),p=b.window.mydoxCloudTestLogin('doctor_2');b.reply({type:'mydox:role-response',requestId:'request-one',error:true});await assert.rejects(p);
});
