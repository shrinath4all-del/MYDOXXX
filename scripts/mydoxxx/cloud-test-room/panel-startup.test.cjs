'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const P=require('./panel-startup.js');
function environment(url='https://mydoxxx-live-test.netlify.app/panel/?role=patient_2&autologin=1'){
  const events={},timers=new Map(),messages=[];let timerId=0,reloads=0;
  class Node{
    constructor(tag){this.tagName=tag;this.children=[];this.style={};this.listeners={};this.hidden=false;}
    setAttribute(){} append(...children){this.children.push(...children);} remove(){this.removed=true;}
    addEventListener(name,fn){this.listeners[name]=fn;}
  }
  const body=new Node('body'),fallback=new Node('p');
  const location=new URL(url);location.reload=()=>{reloads++;};
  const win={location,document:{body,createElement:tag=>new Node(tag),getElementById:()=>fallback},
    parent:{postMessage:(data,origin)=>messages.push({data,origin})},
    setTimeout:(fn,delay)=>{const id=++timerId;timers.set(id,{fn,delay});return id;},clearTimeout:id=>timers.delete(id),
    addEventListener:(name,fn)=>(events[name]??=[]).push(fn)};
  return {win,body,fallback,timers,messages,emit:(name,event={})=>(events[name]||[]).forEach(fn=>fn(event)),get reloads(){return reloads;}};
}
test('a stalled app gets visible retry after45seconds, not a false ready signal',()=>{
  const e=environment(),boot=P.install(e.win),box=e.body.children[0];
  assert.equal(box.children[1].textContent,'Loading your app…');assert.equal(box.children[3].hidden,true);
  const timer=[...e.timers.values()][0];assert.equal(timer.delay,45000);timer.fn();
  assert.equal(boot.state,'slow');assert.equal(box.children[3].hidden,false);
  assert.match(box.children[2].textContent,/keep waiting/);assert.equal(e.messages.at(-1).data.state,'slow');
  assert.ok(e.messages.every(m=>m.data.roleKey==='patient_2'&&m.origin==='https://mydoxxx-live-test.netlify.app'));
  box.children[3].listeners.click();assert.equal(e.reloads,1);
  assert.equal(e.win.location.search,'?role=patient_2&autologin=1');
});
test('first frame removes overlay and recovers a slow load without reloading',()=>{
  const e=environment(),boot=P.install(e.win),box=e.body.children[0];
  [...e.timers.values()][0].fn();e.emit('flutter-first-frame');
  assert.equal(boot.state,'ready');assert.equal(box.removed,true);assert.equal(e.timers.size,0);
  assert.equal(e.messages.at(-1).data.state,'ready');assert.equal(e.reloads,0);
  e.emit('unhandledrejection');assert.equal(boot.state,'ready');assert.equal(e.messages.at(-1).data.state,'ready');
});
test('engine initialization failures are caught and do not leak raw errors',async()=>{
  const e=environment(),boot=P.install(e.win);let config;
  await e.win.MyDoxPanelStartup.startEngine({initializeEngine:async c=>{config=c;throw Error('PRIVATE_ERROR_VALUE');}});
  assert.deepEqual(config,P.ENGINE_CONFIG);assert.equal(boot.state,'failed');assert.equal(e.timers.size,0);
  assert.equal(e.body.children[0].children[3].hidden,false);
  assert.ok(!JSON.stringify(e.messages).includes('PRIVATE_ERROR_VALUE'));
});
test('successful runApp does not report ready until actual first frame',async()=>{
  const e=environment(),boot=P.install(e.win);let ran=0;
  await e.win.MyDoxPanelStartup.startEngine({initializeEngine:async()=>({runApp:async()=>{ran++;}})});
  assert.equal(ran,1);assert.equal(boot.state,'loading');e.emit('flutter-first-frame');assert.equal(boot.state,'ready');
});
test('failed main script gives retry; unrelated image failures do not',()=>{
  const e=environment(),boot=P.install(e.win);
  e.emit('error',{target:{src:'https://mydoxxx-live-test.netlify.app/panel/assets/picture.png'}});assert.equal(boot.state,'loading');
  e.emit('error',{target:{src:'https://mydoxxx-live-test.netlify.app/panel/main.dart.js'}});assert.equal(boot.state,'failed');
});
test('startup adapter refuses an unapproved host or non-panel path',()=>{
  for(const url of ['https://example.com/panel/?role=patient','https://mydoxxx-live-test.netlify.app/']){
    const e=environment(url);assert.equal(P.install(e.win),undefined);assert.equal(e.body.children.length,0);assert.equal(e.messages.length,0);
  }
});
test('panel document aliases still show startup feedback without changing login guards',()=>{
  for(const path of ['/panel','/panel/index.html']){
    const e=environment('https://mydoxxx-live-test.netlify.app'+path+'?role=doctor&autologin=1');
    assert.equal(P.install(e.win).state,'loading');assert.equal(e.body.children.length,1);
    assert.equal(e.messages[0].data.roleKey,'doctor');
  }
});
