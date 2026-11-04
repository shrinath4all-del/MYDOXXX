'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const S=require('./test-console-state.js');
function fixture(){let port=12000;return {projectId:S.PROJECT,databaseId:S.DATABASE,roles:Object.keys(S.FAMILIES).flatMap(family=>[1,2,3].map(person=>{const key=S.keyFor(family,person);return {key,family,person,label:S.FAMILIES[family]+' '+person,uid:'mdxtest'+key.replaceAll('_',''),url:`http://127.0.0.1:${port++}/?role=${key}&autologin=1`};}))};}
const catalog=()=>S.validateCatalog(fixture());
test('catalogue requires three distinct accounts for each of twelve families',()=>{const c=catalog();assert.equal(c.length,36);assert.equal(new Set(c.map(r=>r.uid)).size,36);for(const f of Object.keys(S.FAMILIES))assert.deepEqual(c.filter(r=>r.family===f).map(r=>r.person),[1,2,3]);});
test('catalogue refuses unexpected backend, mismatched UID, external URL and duplicate origin',()=>{for(const change of [d=>d.projectId='original',d=>d.roles.pop(),d=>d.roles[1].uid=d.roles[0].uid,d=>d.roles[0].url='https://example.com/',d=>d.roles[1].url=d.roles[1].url.replace(':12001',':12000')]){const d=fixture();change(d);assert.throws(()=>S.validateCatalog(d));}});
test('public catalogue objects discard injected credential fields',()=>{const d=fixture();d.roles[0].password='MUST-NOT-PERSIST';const c=S.validateCatalog(d);assert.equal(c[0].password,undefined);assert.deepEqual(Object.keys(c[0]).sort(),['family','key','label','person','uid','url']);});
test('selection is unique, supports all36 and filters unknown identities',()=>{const c=catalog(),all=c.map(r=>r.key);assert.equal(S.selection(all,c).length,36);assert.deepEqual(S.selection(['patient','patient','doctor_2','admin'],c),['patient','doctor_2']);assert.deepEqual(S.toggle(['patient'],'doctor_2',true,c),['patient','doctor_2']);assert.deepEqual(S.toggle(['patient','doctor_2'],'patient',false,c),['doctor_2']);});
test('saved layout stores keys and columns only and restores explicit empty selection',()=>{const c=catalog(),raw=S.serializeLayout(['doctor_3','patient','invalid'],3,c);assert.deepEqual(JSON.parse(raw),{version:2,selected:['doctor_3','patient'],columns:3});assert.deepEqual(S.parseLayout(raw,c),{selected:['doctor_3','patient'],columns:3});assert.deepEqual(S.parseLayout('{"version":2,"selected":[],"columns":2,"password":"injected"}',c),{selected:[],columns:2});assert.equal(S.parseLayout('invalid',c),null);assert.equal(S.parseLayout('{"version":2,"selected":[],"columns":99}',c),null);});
test('single-account replacement never creates a duplicate or changes peers',()=>{const c=catalog(),keys=['patient','doctor','nurse'];assert.deepEqual(S.replace(keys,'doctor','doctor_3',c),['patient','doctor_3','nurse']);assert.deepEqual(S.replace(keys,'doctor','nurse',c),keys);});
test('panel reconciliation preserves retained objects and never re-inserts them',()=>{const panels=new Map(),inserted=[],removed=[];const adapter={create:key=>({key,state:'in-progress'}),insert:p=>inserted.push(p),remove:p=>removed.push(p),order:(p,i)=>p.order=i};S.reconcilePanels(panels,['patient','doctor'],adapter);const patient=panels.get('patient'),doctor=panels.get('doctor');S.reconcilePanels(panels,['doctor','patient','doctor_2'],adapter);assert.equal(panels.get('patient'),patient);assert.equal(panels.get('doctor'),doctor);assert.equal(inserted.filter(p=>p===patient).length,1);assert.equal(inserted.filter(p=>p===doctor).length,1);assert.equal(patient.state,'in-progress');S.reconcilePanels(panels,['doctor','doctor_2'],adapter);assert.deepEqual(removed,[patient]);assert.equal(panels.get('doctor'),doctor);});

// Minimal DOM adapter exercises the actual console script without a browser,
// Flutter, network or real credentials. Source assignments and reparenting are
// recorded to catch accidental reloads of unaffected iframe panels.
class Element {
  constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.listeners={};this.attributes={};this.dataset={};this.parentNode=null;this.value='';this.style={setProperty:(k,v)=>{this.style[k]=v;}};this.classes=new Set();this.classList={toggle:(k,on)=>{if(on===undefined)on=!this.classes.has(k);if(on)this.classes.add(k);else this.classes.delete(k);return on;}};this.sourceWrites=0;this.reparentings=0;this.clientWidth=360;this.clientHeight=640;this.inert=false;}
  set src(value){this._src=value;this.sourceWrites++;}get src(){return this._src;}
  append(...nodes){for(const n of nodes){if(n.parentNode){n.reparentings++;n.remove();}n.parentNode=this;this.children.push(n);if(this.tagName==='SELECT'&&this.value==='')this.value=String(n.value);}}
  remove(){if(this.parentNode){this.parentNode.children=this.parentNode.children.filter(n=>n!==this);this.parentNode=null;}}
  replaceChildren(...nodes){for(const n of [...this.children])n.remove();this.append(...nodes);}
  setAttribute(k,v){this.attributes[k]=String(v);}
  removeAttribute(k){delete this.attributes[k];}
  focus(){this.focused=true;}
  addEventListener(type,handler){(this.listeners[type]??=[]).push(handler);}
  fire(type,extra={}){for(const fn of this.listeners[type]??[])fn({target:this,preventDefault(){},...extra});}
  scrollIntoView(){}
}
async function mount(saved,phonePreference){
 const nodes=[],ids=new Map(),documentEvents={},windowEvents={};
 const make=tag=>{const n=new Element(tag);nodes.push(n);return n;};
 const body=make('body');
 for(const id of ['room','families','selectionStatus','savedStatus','addFamily','addPerson','addPanel','panelCount','performanceWarning','reloadAll','empty','selectAll','selectNone','familySearch','columns','guideButton','guide','accountPicker','phoneFrame']){const n=make(['addFamily','addPerson','columns'].includes(id)?'select':'div');n.id=id;ids.set(id,n);}
 ids.get('addPerson').value='1';ids.get('room').append(ids.get('empty'));
 const presets=Object.keys(S.PRESETS).map(key=>{const n=make('button');n.dataset.preset=key;n.textContent=key;return n;});
 const memory=new Map();if(saved!==undefined)memory.set('mydoxxx-test-room-layout-v2',saved);if(phonePreference!==undefined)memory.set('mydoxxx-test-room-phone-frame',phonePreference);
 const document={body,createElement:make,getElementById:id=>ids.get(id),querySelectorAll:q=>q==='[data-preset]'?presets:q.startsWith('.top,')?[ids.get('accountPicker')]:[],addEventListener:(type,handler)=>(documentEvents[type]??=[]).push(handler)};
 const localStorage={getItem:k=>memory.get(k)??null,setItem:(k,v)=>memory.set(k,v)};
 const window={MyDoxConsoleState:S,innerWidth:1440,addEventListener:(type,handler)=>(windowEvents[type]??=[]).push(handler)};
 class ResizeObserver{constructor(fn){this.fn=fn;}observe(){this.fn();}disconnect(){this.disconnected=true;}}
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'test-console.js'),'utf8'),{window,document,localStorage,ResizeObserver,fetch:async()=>({ok:true,json:async()=>fixture()}),URL,console});
 await new Promise(setImmediate);
 const descendants=n=>n?[n,...n.children.flatMap(descendants)]:[];
 const cards=()=>ids.get('room').children.filter(n=>n.dataset.accountKey);
 const card=key=>cards().find(n=>n.dataset.accountKey===key);
 const frame=key=>descendants(card(key)).find(n=>n.tagName==='IFRAME');
 const control=(key,action)=>descendants(card(key)).find(n=>n.dataset.action===action);
 const viewport=key=>descendants(card(key)).find(n=>n.className==='pane-viewport');
 const check=key=>nodes.find(n=>n.tagName==='INPUT'&&n.value===key);
 const keydown=key=>{for(const fn of documentEvents.keydown??[])fn({key,preventDefault(){}});};
 const resize=()=>{for(const fn of windowEvents.resize??[])fn();};
 return {ids,nodes,memory,presets,cards,card,frame,check,control,viewport,body,keydown,resize};
}

test('actual UI loads only default4, then adds/removes one without reloading peers',async()=>{const ui=await mount();assert.equal(ui.cards().length,4);const patient=ui.frame('patient'),doctor=ui.frame('doctor');assert.equal(patient.sourceWrites,1);ui.check('doctor_2').checked=true;ui.check('doctor_2').fire('change');assert.equal(ui.cards().length,5);assert.equal(ui.frame('patient'),patient);assert.equal(ui.frame('doctor'),doctor);assert.equal(patient.sourceWrites,1);assert.equal(patient.reparentings,0);ui.check('doctor_2').checked=false;ui.check('doctor_2').fire('change');assert.equal(ui.cards().length,4);assert.equal(patient.sourceWrites,1);assert.equal(doctor.sourceWrites,1);});
test('quick preset preserves shared panes; columns do not reload any pane',async()=>{const ui=await mount(),patient=ui.frame('patient'),doctor=ui.frame('doctor');ui.presets.find(p=>p.dataset.preset==='doctors').fire('click');assert.equal(ui.cards().length,4);assert.equal(ui.frame('patient'),patient);assert.equal(ui.frame('doctor'),doctor);ui.ids.get('columns').value='3';ui.ids.get('columns').fire('change');assert.equal(patient.sourceWrites,1);assert.equal(doctor.sourceWrites,1);assert.equal(ui.ids.get('room').style['--cols'],3);});
test('all36 can be selected explicitly and selectnone closes only app views',async()=>{const ui=await mount();ui.ids.get('selectAll').fire('click');assert.equal(ui.cards().length,36);assert.equal(ui.ids.get('performanceWarning').hidden,false);ui.ids.get('selectNone').fire('click');assert.equal(ui.cards().length,0);assert.equal(ui.ids.get('empty').hidden,false);const stored=JSON.parse(ui.memory.get('mydoxxx-test-room-layout-v2'));assert.deepEqual(stored.selected,[]);assert.deepEqual(Object.keys(stored).sort(),['columns','selected','version']);});
test('saved identity selection restores exact accounts and safe individual-tab links',async()=>{const ui=await mount(JSON.stringify({version:2,selected:['patient_3','doctor_2'],columns:2,password:'never stored'}));assert.deepEqual(ui.cards().map(p=>p.dataset.accountKey),['patient_3','doctor_2']);assert.equal(ui.frame('patient_3').title,'Patients 3 · mdxtestpatient3');const links=ui.nodes.filter(n=>n.tagName==='A');assert.equal(links.length,2);for(const link of links){assert.equal(link.target,'_blank');assert.equal(link.rel,'noopener noreferrer');assert.ok(link.href.startsWith('http://127.0.0.1:'));}assert.ok(!ui.memory.get('mydoxxx-test-room-layout-v2').includes('password'));});


test('zoom changes only its existing iframe viewport, clamps60–140 and reset retains session',async()=>{
 const ui=await mount(),doctor=ui.frame('doctor'),patient=ui.frame('patient'),patientWidth=patient.style.width;
 ui.control('doctor','zoom-out').fire('click');
 assert.equal(doctor.style.transform,'scale(0.9)');assert.equal(doctor.style.width,'400px');assert.equal(doctor.style.height,'712px');
 assert.equal(doctor.parentNode.style.width,'360px');assert.equal(doctor.parentNode.style.height,'640px');
 assert.equal(patient.style.width,patientWidth);assert.equal(patient.style.transform,'scale(1)');assert.equal(ui.frame('doctor'),doctor);
 for(let n=0;n<10;n++)ui.control('doctor','zoom-out').fire('click');
 assert.equal(ui.control('doctor','zoom-reset').textContent,'60%');assert.equal(ui.control('doctor','zoom-out').disabled,true);
 for(let n=0;n<20;n++)ui.control('doctor','zoom-in').fire('click');
 assert.equal(ui.control('doctor','zoom-reset').textContent,'140%');assert.equal(ui.control('doctor','zoom-in').disabled,true);
 ui.control('doctor','zoom-reset').fire('click');assert.equal(doctor.style.transform,'scale(1)');
 assert.equal(doctor.sourceWrites,1);assert.equal(patient.sourceWrites,1);assert.equal(doctor.reparentings,0);assert.equal(patient.reparentings,0);
});

test('expand, resize and Escape restore preserve every iframe and selected account',async()=>{
 const ui=await mount(),doctor=ui.frame('doctor'),patient=ui.frame('patient'),doctorParent=doctor.parentNode,saved=ui.memory.get('mydoxxx-test-room-layout-v2');
 ui.control('doctor','zoom-out').fire('click');ui.control('doctor','expand').fire('click');
 assert.equal(ui.card('doctor').classes.has('expanded'),true);assert.equal(ui.card('doctor').attributes['aria-modal'],'true');
 assert.equal(ui.card('patient').inert,true);assert.equal(ui.ids.get('accountPicker').inert,true);
 assert.equal(ui.control('doctor','expand').textContent,'Restore');
 ui.viewport('doctor').clientWidth=1000;ui.viewport('doctor').clientHeight=800;ui.resize();
 assert.equal(doctor.style.width,'1112px');assert.equal(doctor.style.height,'889px');
 ui.keydown('Escape');
 assert.equal(ui.card('doctor').classes.has('expanded'),false);assert.equal(ui.card('doctor').attributes['aria-modal'],undefined);
 assert.equal(ui.card('patient').inert,false);assert.equal(ui.ids.get('accountPicker').inert,false);assert.equal(ui.control('doctor','expand').focused,true);
 assert.equal(ui.ids.get('selectionStatus').textContent,'Restored Cardiologists 1 to the test room. All screens kept their sessions.');
 assert.equal(ui.frame('doctor'),doctor);assert.equal(doctor.parentNode,doctorParent);assert.equal(doctor.reparentings,0);assert.equal(doctor.sourceWrites,1);assert.equal(patient.sourceWrites,1);
 assert.equal(ui.memory.get('mydoxxx-test-room-layout-v2'),saved);
});

test('backdrop and Restore close focus view; removing expanded panel releases background',async()=>{
 const ui=await mount(),patient=ui.frame('patient');
 ui.control('doctor','expand').fire('click');ui.nodes.find(n=>n.className==='pane-backdrop').fire('click');
 assert.equal(ui.body.classes.has('panel-expanded'),false);
 ui.control('doctor','expand').fire('click');ui.control('doctor','expand').fire('click');
 assert.equal(ui.card('doctor').classes.has('expanded'),false);
 ui.control('doctor','expand').fire('click');ui.check('doctor').checked=false;ui.check('doctor').fire('change');
 assert.equal(ui.card('doctor'),undefined);assert.equal(ui.card('patient').inert,false);assert.equal(ui.body.classes.has('panel-expanded'),false);
 assert.equal(ui.ids.get('selectionStatus').textContent,'Closed Cardiologists 1. Other screens stay running.');
 assert.equal(ui.frame('patient'),patient);assert.equal(patient.sourceWrites,1);
});


test('phone presentation defaults on and toggles without moving or reloading any iframe',async()=>{
 const ui=await mount(),doctor=ui.frame('doctor'),patient=ui.frame('patient'),parent=doctor.parentNode;
 assert.equal(ui.ids.get('phoneFrame').checked,true);assert.equal(ui.ids.get('room').classes.has('phone-mode'),true);
 const shell=ui.nodes.find(n=>n.className==='device-shell'&&n===doctor.parentNode.parentNode.parentNode);
 assert.ok(shell);assert.deepEqual(shell.children.map(n=>n.className),['device-top','pane-viewport','device-bottom']);
 ui.ids.get('phoneFrame').checked=false;ui.ids.get('phoneFrame').fire('change');
 assert.equal(ui.ids.get('room').classes.has('phone-mode'),false);assert.equal(ui.memory.get('mydoxxx-test-room-phone-frame'),'0');
 assert.equal(ui.frame('doctor'),doctor);assert.equal(doctor.parentNode,parent);assert.equal(doctor.sourceWrites,1);assert.equal(doctor.reparentings,0);assert.equal(patient.sourceWrites,1);
 ui.ids.get('phoneFrame').checked=true;ui.ids.get('phoneFrame').fire('change');
 assert.equal(ui.frame('doctor'),doctor);assert.equal(doctor.sourceWrites,1);assert.equal(ui.memory.get('mydoxxx-test-room-phone-frame'),'1');
});

test('narrow phone screen fits logical app width and preserves independent zoom through plain view',async()=>{
 const ui=await mount(),doctor=ui.frame('doctor');ui.viewport('doctor').clientWidth=288;ui.viewport('doctor').clientHeight=576;ui.resize();
 assert.equal(doctor.style.width,'360px');assert.equal(doctor.style.height,'720px');assert.equal(doctor.style.transform,'scale(0.8)');
 assert.equal(doctor.parentNode.style.width,'288px');assert.equal(doctor.parentNode.style.height,'576px');
 ui.control('doctor','zoom-out').fire('click');assert.equal(ui.control('doctor','zoom-reset').textContent,'90%');
 ui.ids.get('phoneFrame').checked=false;ui.ids.get('phoneFrame').fire('change');
 assert.equal(ui.control('doctor','zoom-reset').textContent,'90%');assert.equal(doctor.style.transform,'scale(0.9)');assert.equal(doctor.sourceWrites,1);
 const restored=await mount(undefined,'0');assert.equal(restored.ids.get('phoneFrame').checked,false);assert.equal(restored.ids.get('room').classes.has('phone-mode'),false);
});
