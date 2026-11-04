(function() {
  'use strict';
  const S=window.MyDoxConsoleState, $=id=>document.getElementById(id);
  const STORAGE_KEY='mydoxxx-test-room-layout-v2';
  const PHONE_KEY='mydoxxx-test-room-phone-frame';
  const room=$('room'), panels=new Map(), checks=new Map(), groups=new Map();
  let catalogue=[], byKey=new Map(), selected=[], columns=window.innerWidth<800?1:window.innerWidth<1900?2:4, storageOk=true, expanded=null, phoneFrame=true;
  const backdrop=node('div','pane-backdrop');backdrop.hidden=true;backdrop.setAttribute('aria-hidden','true');document.body.append(backdrop);
  let inertBefore=new Map();
  const familyMarks={patient:'PT',doctor:'DR',nurse:'NU',hospital:'HP',ambulance:'AM',care_physician:'CP',technician:'TC',therapist:'PH',agency_care:'CA',agency_nurse:'NA',agency_technician:'TA',agency_physio:'PA'};
  function node(tag,className,text) { const n=document.createElement(tag); if(className)n.className=className;if(text!==undefined)n.textContent=text;return n; }
  function button(className,text,label) {const n=node('button',className,text);n.type='button';n.setAttribute('aria-label',label);n.title=label;return n;}
  function say(text){$('selectionStatus').textContent=text;}
  function save(){try{localStorage.setItem(STORAGE_KEY,S.serializeLayout(selected,columns,catalogue));storageOk=true;}catch(_){storageOk=false;}$('savedStatus').textContent=storageOk?'Layout saved on this computer · no passwords saved':'Layout is active · browser storage is unavailable';}
  function familyOptions(select){for(const [key,label] of Object.entries(S.FAMILIES)){const o=node('option','',label);o.value=key;select.append(o);}}
  function populatePicker(){
    const container=$('families');
    for(const [family,label] of Object.entries(S.FAMILIES)){
      const field=node('fieldset','family');field.dataset.family=family;field.setAttribute('aria-label',label);
      const head=node('div','family-head'),groupLabel=node('label'),all=node('input');all.type='checkbox';all.setAttribute('aria-label','Select all three '+label.toLowerCase());
      groupLabel.append(all,node('span','',label));head.append(groupLabel,node('span','family-glyph',familyMarks[family]));
      const people=node('div','person-options');
      for(const person of [1,2,3]){const key=S.keyFor(family,person),identity=byKey.get(key),labelNode=node('label','person'),check=node('input');check.type='checkbox';check.value=key;check.setAttribute('aria-label','Show '+identity.label);labelNode.title=identity.label+' · UID '+identity.uid;labelNode.append(check,node('span','',''+person));people.append(labelNode);checks.set(key,{check,label:labelNode});check.addEventListener('change',()=>apply(S.toggle(selected,key,check.checked,catalogue),check.checked?'Opened '+identity.label+'. Other screens stay running.':'Closed '+identity.label+'. Other screens stay running.'));}
      all.addEventListener('change',()=>{const keys=[1,2,3].map(n=>S.keyFor(family,n));apply(all.checked?S.selection([...selected,...keys],catalogue):selected.filter(k=>!keys.includes(k)),(all.checked?'Opened':'Closed')+' all '+label.toLowerCase()+'.');});
      field.append(head,people);container.append(field);groups.set(family,{all,field});
    }
  }
  function restorePanel(focus=true){
    if(!expanded)return;
    const p=expanded;expanded=null;p.card.classList.toggle('expanded',false);
    p.card.removeAttribute('role');p.card.removeAttribute('aria-modal');p.card.removeAttribute('aria-label');
    p.expand.textContent='Expand';p.expand.setAttribute('aria-expanded','false');p.expand.title='Expand '+p.identity.label;
    backdrop.hidden=true;document.body.classList.toggle('panel-expanded',false);
    for(const [element,value] of inertBefore)element.inert=value;inertBefore.clear();
    p.resize();if(focus){p.expand.focus({preventScroll:true});say('Restored '+p.identity.label+' to the test room. All screens kept their sessions.');}
  }
  function expandPanel(p){
    if(expanded===p){restorePanel();return;}
    restorePanel(false);expanded=p;backdrop.hidden=false;document.body.classList.toggle('panel-expanded',true);
    for(const element of [...document.querySelectorAll('.top,.presets,.bounds,#guide,#accountPicker,.room-toolbar,.quick-add'),...Array.from(panels.values(),item=>item.card)]){
      if(element===p.card)continue;inertBefore.set(element,Boolean(element.inert));element.inert=true;
    }
    p.card.classList.toggle('expanded',true);p.card.setAttribute('role','dialog');p.card.setAttribute('aria-modal','true');p.card.setAttribute('aria-label','Expanded '+p.identity.label+' app view');
    p.expand.textContent='Restore';p.expand.setAttribute('aria-expanded','true');p.expand.title='Restore '+p.identity.label+' to the test room';
    p.resize();p.expand.focus({preventScroll:true});say('Expanded '+p.identity.label+'. Its session and other screens stay running. Use Restore to return.');
  }
  backdrop.addEventListener('click',()=>restorePanel());
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&expanded){event.preventDefault();restorePanel();}});
  window.addEventListener('resize',()=>{for(const p of panels.values())p.resize();});
  function makePanel(key){
    const identity=byKey.get(key),card=node('section','pane');card.dataset.accountKey=key;
    const head=node('div','pane-head'),number=node('span','number'),identityBox=node('div','pane-identity'),selectors=node('div','pane-selectors');
    const family=node('select'),person=node('select');familyOptions(family);family.value=identity.family;family.setAttribute('aria-label','Role for '+identity.label);
    for(const n of [1,2,3]){const o=node('option','','#'+n);o.value=n;person.append(o);}person.value=identity.person;person.setAttribute('aria-label','Account number for '+identity.label);
    const uid=node('code','','UID · '+identity.uid);uid.title='Exact Firebase test account: '+identity.uid;selectors.append(family,person);identityBox.append(selectors,uid);
    const actions=node('div','pane-actions'),refresh=button('icon','↻','Reload '+identity.label),open=node('a','icon','↗'),remove=button('icon remove','×','Remove '+identity.label);
    open.href=identity.url;open.target='_blank';open.rel='noopener noreferrer';open.title='Open '+identity.label+' in a separate tab';open.setAttribute('aria-label',open.title);
    actions.append(refresh,open,remove);head.append(number,identityBox,actions);
    const tools=node('div','pane-view-tools'),zoomTools=node('div','pane-zoom');
    zoomTools.setAttribute('role','group');zoomTools.setAttribute('aria-label','Zoom for '+identity.label);
    const zoomOut=button('view-button','−','Zoom out '+identity.label),zoomReset=button('view-button zoom-value','100%','Reset zoom for '+identity.label),zoomIn=button('view-button','+','Zoom in '+identity.label),expand=button('view-button expand-view','Expand','Expand or restore '+identity.label);
    zoomOut.dataset.action='zoom-out';zoomReset.dataset.action='zoom-reset';zoomIn.dataset.action='zoom-in';expand.dataset.action='expand';expand.setAttribute('aria-expanded','false');
    zoomReset.title='Reset this screen to 100%';zoomTools.append(zoomOut,zoomReset,zoomIn);tools.append(zoomTools,node('span','view-hint','This screen only'),expand);
    const shell=node('div','device-shell'),deviceTop=node('div','device-top'),deviceBottom=node('div','device-bottom');
    deviceTop.setAttribute('aria-hidden','true');deviceBottom.setAttribute('aria-hidden','true');
    const deviceIcons=node('span','device-icons'),signal=node('span','device-signal');signal.append(node('i'),node('i'),node('i'));
    deviceIcons.append(signal,node('span','device-wifi','⌁'),node('span','device-battery'));
    deviceTop.append(node('span','device-time','9:41'),node('span','device-island'),deviceIcons);deviceBottom.append(node('span','device-home'));
    const viewport=node('div','pane-viewport'),stage=node('div','pane-stage'),frame=node('iframe','pane-frame');frame.title=identity.label+' · '+identity.uid;frame.allow='clipboard-write';
    viewport.setAttribute('aria-label','Scrollable '+identity.label+' app viewport');viewport.tabIndex=0;stage.append(frame);viewport.append(stage);shell.append(deviceTop,viewport,deviceBottom);
    const status=node('span','','Opening app…'),foot=node('div','pane-foot');foot.append(status,node('span','','Account '+identity.person+' · shared data'));
    const panel={card,frame,number,identity,status,viewport,stage,shell,expand,zoom:100,resize};
    function resize(){
      const w=viewport.clientWidth||315,h=viewport.clientHeight||620;
      const scale=panel.zoom/100*(phoneFrame?Math.min(1,w/360):1);
      const logicalW=Math.max(320,Math.ceil(w/scale)),logicalH=Math.max(480,Math.ceil(h/scale));
      frame.style.width=logicalW+'px';frame.style.height=logicalH+'px';frame.style.transform='scale('+scale+')';
      // Keep fractional rounding from creating unnecessary one-pixel scrollbars.
      stage.style.width=Math.max(w,320*scale)+'px';stage.style.height=Math.max(h,480*scale)+'px';
    }
    function setZoom(value){
      panel.zoom=Math.min(140,Math.max(60,value));zoomReset.textContent=panel.zoom+'%';zoomOut.disabled=panel.zoom===60;zoomIn.disabled=panel.zoom===140;resize();
      say(identity.label+' zoom '+panel.zoom+'%. Other screens are unchanged.');
    }
    zoomOut.addEventListener('click',()=>setZoom(panel.zoom-10));zoomIn.addEventListener('click',()=>setZoom(panel.zoom+10));zoomReset.addEventListener('click',()=>setZoom(100));expand.addEventListener('click',()=>expandPanel(panel));
    panel.observer=typeof ResizeObserver==='function'?new ResizeObserver(resize):null;panel.observer?.observe(viewport);resize();
    // Set source once. Zoom and expansion only resize/style the same iframe.
    frame.addEventListener('load',()=>{status.textContent='App view loaded';resize();});frame.src=identity.url;card.append(head,tools,shell,foot);
    refresh.addEventListener('click',()=>{status.textContent='Reloading app…';frame.src=identity.url;say('Reloading only '+identity.label+'.');});
    remove.addEventListener('click',()=>apply(selected.filter(k=>k!==key),'Closed '+identity.label+'. Other screens stay running.'));
    function switchIdentity(){const next=S.keyFor(family.value,Number(person.value));if(next===key)return;if(selected.includes(next)){family.value=identity.family;person.value=identity.person;say(byKey.get(next).label+' is already open. Each account has one panel.');panels.get(next).card.scrollIntoView({block:'nearest',behavior:'smooth'});return;}apply(S.replace(selected,key,next,catalogue),'Changed this screen to '+byKey.get(next).label+'. Other screens stay running.');}
    family.addEventListener('change',switchIdentity);person.addEventListener('change',switchIdentity);
    return panel;
  }
  const adapter={create:makePanel,insert:p=>{room.append(p.card);p.resize();},remove:p=>{if(expanded===p)restorePanel(false);p.observer?.disconnect();p.frame.src='about:blank';p.card.remove();},order:(p,i)=>{p.card.style.order=i;p.number.textContent=i+1;}};
  function updateControls(){
    for(const [key,item] of checks){item.check.checked=selected.includes(key);item.label.classList.toggle('chosen',item.check.checked);}
    for(const [family,group] of groups){const count=[1,2,3].filter(n=>selected.includes(S.keyFor(family,n))).length;group.all.checked=count===3;group.all.indeterminate=count>0&&count<3;}
    $('panelCount').textContent=selected.length+' '+(selected.length===1?'screen':'screens')+' open';
    $('performanceWarning').hidden=selected.length<=8;
    $('reloadAll').disabled=selected.length===0;
    $('empty').hidden=selected.length>0;
    if(!selected.length){$('empty').replaceChildren(node('b','','Your test room is ready'),node('p','','Choose accounts from the picker, add one screen, or try a quick layout. Shared test data stays saved when you close a screen.'));}
    for(const b of document.querySelectorAll('[data-preset]')){const keys=S.PRESETS[b.dataset.preset];b.classList.toggle('active',selected.length===keys.length&&keys.every(k=>selected.includes(k)));}
    updateAddButton();
  }
  function apply(next,message){selected=S.selection(next,catalogue);S.reconcilePanels(panels,selected,adapter);updateControls();save();if(message)say(message);}
  function updateAddButton(){const key=S.keyFor($('addFamily').value,Number($('addPerson').value));const exists=selected.includes(key);$('addPanel').disabled=exists;$('addPanel').textContent=exists?'Already open':'Add screen';}
  function initialize(){
    try{phoneFrame=localStorage.getItem(PHONE_KEY)!=='0';}catch(_){phoneFrame=true;}
    $('phoneFrame').checked=phoneFrame;room.classList.toggle('phone-mode',phoneFrame);
    $('phoneFrame').addEventListener('change',()=>{
      phoneFrame=$('phoneFrame').checked;room.classList.toggle('phone-mode',phoneFrame);
      try{localStorage.setItem(PHONE_KEY,phoneFrame?'1':'0');}catch(_){}
      for(const p of panels.values())p.resize();
      say(phoneFrame?'iPhone presentation frame on. App sessions stay running.':'Plain app view on. App sessions stay running.');
    });
    populatePicker();familyOptions($('addFamily'));$('addFamily').value='doctor';
    $('addFamily').addEventListener('change',updateAddButton);$('addPerson').addEventListener('change',updateAddButton);
    $('addPanel').addEventListener('click',()=>{const key=S.keyFor($('addFamily').value,Number($('addPerson').value));apply([...selected,key],'Opened '+byKey.get(key).label+'. Other screens stay running.');});
    $('selectAll').addEventListener('click',()=>apply(catalogue.map(r=>r.key),'All 36 accounts selected. You can close individual screens at any time.'));
    $('selectNone').addEventListener('click',()=>apply([],'All screens closed. Shared bookings and messages remain in the test database.'));
    $('familySearch').addEventListener('input',()=>{const query=$('familySearch').value.trim().toLowerCase();for(const [family,group] of groups)group.field.classList.toggle('hidden',!(S.FAMILIES[family]+' '+family).toLowerCase().includes(query));});
    for(const b of document.querySelectorAll('[data-preset]'))b.addEventListener('click',()=>apply(S.PRESETS[b.dataset.preset],b.textContent+' layout opened. Any accounts already open keep their current screen.'));
    $('columns').addEventListener('change',()=>{columns=Number($('columns').value);room.style.setProperty('--cols',columns);save();});
    $('reloadAll').addEventListener('click',()=>{for(const p of panels.values()){p.status.textContent='Reloading app…';p.frame.src=p.identity.url;}say('Reloading the selected screens. Test records remain saved.');});
    let restored=null;try{restored=S.parseLayout(localStorage.getItem(STORAGE_KEY),catalogue);}catch(_){storageOk=false;}
    if(restored)columns=restored.columns;
    $('columns').value=columns;room.style.setProperty('--cols',columns);
    apply(restored?restored.selected:S.PRESETS.appointments,restored?'Your saved account selection is restored.':'Start with four accounts, or choose the people you need from the picker.');
  }
  $('guideButton').addEventListener('click',()=>{const show=$('guide').hidden;$('guide').hidden=!show;$('guideButton').setAttribute('aria-expanded',show);});
  fetch('/catalog.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw Error('The local role catalogue is unavailable.');return r.json();}).then(data=>{catalogue=S.validateCatalog(data);byKey=new Map(catalogue.map(r=>[r.key,r]));initialize();}).catch(e=>{$('empty').replaceChildren(node('b','error','The test room could not start'),node('p','',e.message));$('savedStatus').textContent='Local host connection required';say('Start the updated MYDOXXX local test host and reload this page.');for(const b of document.querySelectorAll('.preset,#selectAll,#selectNone,#addPanel,#reloadAll'))b.disabled=true;});
})();
