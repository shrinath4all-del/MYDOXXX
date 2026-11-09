(function () {
  'use strict';
  const D=window.BfastDemo;
  let state=D.initial(),selected=['patient-1','hospital-1','doctor-1','ambulance-1'],scenario='emergency';
  const pages={},drafts={},partners={},limits={};
  const $=id=>document.getElementById(id);
  const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const paths={heart:'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z',doctor:'M6 3v4a4 4 0 0 0 8 0V3M4 3h4m4 0h4M10 11v4a5 5 0 0 0 10 0v-3m-2-2a2 2 0 1 0 4 0 2 2 0 0 0-4 0',hospital:'M5 21V5h14v16M3 21h18M9 9h6m-3-3v6M9 16h2v5m2-5h2v5',ambulance:'M3 7h11v12H3V7Zm11 5h4l3 4v3h-7M7 10v5m-2-2h4M5 19a2 2 0 1 0 4 0m7 0a2 2 0 1 0 4 0',nurse:'M8 4h8l2 5-6 3-6-3 2-5Zm4 2v3m-2-1.5h4M8 12a4 4 0 0 0 8 0M4 21a8 8 0 0 1 16 0',lab:'M9 3h6m-5 0v7L4 19a1.3 1.3 0 0 0 1 2h14a1.3 1.3 0 0 0 1-2l-6-9V3M8 15h8',activity:'M3 12h4l3-8 4 16 3-8h4',team:'M8 7a3 3 0 1 0 6 0 3 3 0 0 0-6 0M3 21v-2a7 7 0 0 1 14 0v2M17 4a3 3 0 0 1 0 6m3 11v-2a6 6 0 0 0-3-5',home:'M3 10 12 3l9 7M5 9v12h14V9m-10 12v-7h6v7',chat:'M21 14a4 4 0 0 1-4 4H8l-5 3V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8ZM7 8h10M7 12h6',calendar:'M5 5h14a2 2 0 0 1 2 2v13H3V7a2 2 0 0 1 2-2ZM7 3v4m10-4v4M3 10h18M7 14h2m3 0h2m3 0h1M7 17h2m3 0h2',bell:'M6 8a6 6 0 0 1 12 0v6l2 3H4l2-3V8ZM10 21h4',shield:'M12 3 3 7v6c0 5 9 9 9 9s9-4 9-9V7l-9-4ZM8 12l3 3 5-6'};
  const icon=name=>'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="'+(paths[name]||paths.heart)+'"></path></svg>';
  const story={
    emergency:{label:'Emergency team',icon:'ambulance',accounts:['patient-1','hospital-1','doctor-1','ambulance-1'],steps:['Patient requests help','Hospital accepts','Doctor + ambulance accept']},
    booking:{label:'Find a doctor',icon:'doctor',accounts:['patient-1','doctor-1','doctor-2','doctor-3'],steps:['Patient books a doctor','Try declining on Doctor 1','Doctor 2 or 3 accepts']},
    home:{label:'Care at home',icon:'home',accounts:['patient-1','nurse-1','technician-1','physio-1'],steps:['Patient chooses a service','Provider accepts','Complete the demo visit']},
    staffing:{label:'Hospital staffing',icon:'team',accounts:['hospital-1','care-1','care-2','agency_care-1'],steps:['Hospital requests an ICU team','Care physicians apply','Sai reviews the shortlist']},
    chat:{label:'Team chat',icon:'chat',accounts:['patient-1','doctor-1','nurse-1','hospital-1'],steps:['Open Chat on a phone','Choose a recipient + send','Reply from the other phone']}
  };
  const person=id=>D.byId[id];
  const name=id=>id&&person(id)?person(id).name:'Waiting';
  const action=(label,type,actor,job='',extra='',cls='')=>'<button class="action '+cls+'" data-action="'+type+'" data-actor="'+actor+'" data-job="'+esc(job)+'" '+extra+'>'+label+'</button>';
  const empty=(heading,text,kind='bell')=>'<div class="empty-card">'+icon(kind)+'<strong>'+heading+'</strong>'+text+'</div>';
  function picker(){
    $('role-picker').innerHTML=D.families.map(f=>'<div class="role-group"><strong>'+esc(f.plural)+'</strong><div class="role-people">'+[1,2,3].map(n=>'<label><input type="checkbox" data-account="'+f.key+'-'+n+'" '+(selected.includes(f.key+'-'+n)?'checked':'')+'>'+n+'</label>').join('')+'</div></div>').join('');
    $('screen-count').textContent=selected.length+' open';
  }
  function drawScenarios(){
    $('scenarios').innerHTML=Object.entries(story).map(([key,s])=>'<button class="scenario '+(key===scenario?'active':'')+'" data-scenario="'+key+'" aria-pressed="'+(key===scenario)+'">'+icon(s.icon)+esc(s.label)+'</button>').join('');
    $('guide').innerHTML='<div class="guide-flow">'+story[scenario].steps.map((s,i)=>'<span><span class="step-tag">'+(i+1)+'</span>'+esc(s)+'</span>').join('<span class="guide-arrow" aria-hidden="true">→</span>')+'</div>';
  }
  function candidateControls(j,id){
    const p=person(id);if(j.status==='completed')return '';
    if(j.kind==='staffing'){
      if(p.family==='care')return j.selected.includes(id)?'<p class="card-detail">✓ Selected for this sample team</p>':j.applicants.includes(id)?'<p class="card-detail">Application sent to Sai</p>':j.status==='applications'?'<div class="actions">'+action('Apply for team','apply',id,j.id)+'</div>':'';
      return '';
    }
    if(j.kind==='emergency'){
      const slot=j.stage==='hospital'&&p.family==='hospital'?'hospital':j.stage==='team'&&['doctor','ambulance'].includes(p.family)?p.family:null;
      if(!slot)return '';
      if(j[slot])return '<p class="card-detail">✓ '+esc(name(j[slot]))+' is assigned</p>';
      if(j.declined.includes(id))return '<p class="card-detail">You declined. Other providers can accept.</p>';
      return '<div class="actions">'+action('Decline','decline',id,j.id,'','danger')+action('Accept request','accept',id,j.id)+'</div>';
    }
    if(!j.candidates.includes(id))return '';
    if(j.assigned)return '<p class="card-detail">✓ '+esc(name(j.assigned))+' is assigned</p>';
    if(j.declined.includes(id))return '<p class="card-detail">You declined. Other providers can accept.</p>';
    return '<div class="actions">'+action('Decline','decline',id,j.id,'','danger')+action('Accept request','accept',id,j.id)+'</div>';
  }
  function jobCard(j,id){
    let content='<article class="request '+(j.kind==='emergency'?'hot':'')+'"><div class="card-title"><strong>'+esc(j.title)+'</strong><span class="chip '+j.status+'">'+esc(j.status)+'</span></div><p class="card-meta">'+esc(name(j.owner))+' · Sample area, Pune<br>Fictional request · '+esc(j.id)+'</p>';
    if(j.kind==='emergency')content+='<div class="timeline">'+[['hospital','Hospital'],['doctor','Cardiologist'],['ambulance','Ambulance']].map(([slot,label])=>'<div class="'+(j[slot]?'done':'')+'"><i>'+(j[slot]?'✓':'·')+'</i><span>'+label+'<br><b>'+esc(name(j[slot]))+'</b></span></div>').join('')+'</div>';
    else if(j.kind==='staffing')content+='<p class="card-detail">'+j.applicants.length+' applied · '+j.selected.length+'/3 selected<br>08–15 · 15–22 · 22–08 rotation</p>';
    else if(j.assigned)content+='<p class="card-detail">Assigned to '+esc(name(j.assigned))+'</p>';
    if(j.kind!=='emergency'&&j.kind!=='staffing'&&!j.assigned&&j.candidates.every(c=>j.declined.includes(c)))content+='<p class="card-detail">No provider accepted. All sample candidates declined. Reset the demo to try again.</p>';
    if(j.kind==='emergency'){
      const pendingSlots=j.stage==='hospital'?['hospital']:j.stage==='team'?['doctor','ambulance']:[];
      for(const slot of pendingSlots)if(!j[slot]&&D.roles(slot).every(c=>j.declined.includes(c)))content+='<p class="card-detail">All sample '+slot+' providers declined. No '+slot+' assigned; reset to try again.</p>';
    }
    content+=candidateControls(j,id);
    if(j.status==='accepted'&&(j.owner===id||j.assigned===id||j.hospital===id))content+='<div class="actions">'+action('Complete demo visit','complete',id,j.id)+'</div>';
    if(j.kind==='staffing'&&id==='agency_care-1'){
      const limit=limits[j.id]||3, ranked=D.ranking(j);
      content+='<div class="tabs-small">'+[3,5,10].map(n=>'<button class="'+(limit===n?'active':'')+'" data-limit="'+n+'" data-job="'+j.id+'">Top '+n+'</button>').join('')+'</div><p class="hint">Illustrative scores, not a clinical assessment. Shows available applicants only; add Care physician 3 to try all three.</p>';
      content+=ranked.length?ranked.slice(0,limit).map((p,i)=>'<div class="team-member"><span class="rank">'+(i+1)+'</span><div class="member-info">'+esc(p.name)+'<small>Sample skills + duty history</small></div><span class="score">'+p.score+'</span>'+(!j.selected.includes(p.id)&&j.status==='applications'?action('Select','select',id,j.id,'data-candidate="'+p.id+'"'): '<span class="chip">Selected</span>')+'</div>').join(''):'<p class="hint">Applications will appear here when a care physician applies.</p>';
    }
    return content+'</article>';
  }
  function patientHome(id){return '<button class="sos" data-action="create" data-kind="emergency" data-actor="'+id+'"><span class="sos-icon">'+icon('bell')+'</span><span><b>Emergency help</b><small>Try coordinated care</small></span><em>›</em></button><h3 class="subhead">How can we help today?</h3><div class="services">'+[['consultation','doctor','Book a cardiologist'],['nursing','nurse','Home nursing'],['lab','lab','Lab collection'],['physio','activity','Physiotherapy']].map(([kind,i,label])=>'<button class="service" data-action="create" data-kind="'+kind+'" data-actor="'+id+'">'+icon(i)+label+'</button>').join('')+'</div><p class="hint">Choose a service, then watch its provider phone.</p>';}
  function roster(id){
    const p=person(id),index=p.number-1,shifts=['Morning','Evening','Night'],order=[[0,2,1],[1,0,2],[2,1,0]][index],times=['08:00–15:00','15:00–22:00','22:00–08:00'];
    const leave=state.leave.find(l=>l.owner===id);
    return '<h3 class="subhead">My sample roster</h3><div class="request"><div class="card-title"><strong>ICU · Sample Hospital</strong><span class="chip">Week 1</span></div><p class="card-meta">'+shifts[order[0]]+' duty · '+times[order[0]]+'</p><div class="roster-grid">'+['M','T','W','T','F','S','S'].map((d,i)=>'<div class="day '+shifts[order[0]].toLowerCase()+'"><span>'+d+'</span><b>'+(i+1)+'</b></div>').join('')+'</div><div class="roster-legend"><span>Morning</span><span>Evening</span><span>Night</span></div>'+order.map((s,i)=>'<div class="roster-week"><span>Week '+(i+1)+'</span><strong>'+shifts[s]+' · '+times[s]+'</strong></div>').join('')+'<p class="hint">Illustrative weekly rotation. This demo does not validate clinical staffing or rest requirements.</p></div>'+(leave?'<div class="request"><strong class="subhead">'+(leave.status==='covered'?'Relief arranged':'Relief requested')+'</strong><p class="card-meta">'+(leave.replacement?esc(name(leave.replacement))+' accepted your sample relief shift.':'Another care physician can accept your relief request.')+'</p></div>':'<div class="actions">'+action('Request relief for tomorrow','leave',id)+'</div>');
  }
  function agencyJobs(id){const mapping={agency_nurse:'nursing',agency_tech:'lab',agency_physio:'physio'};return state.jobs.filter(j=>j.kind===mapping[person(id).family]);}
  function home(id){
    const p=person(id),isPatient=p.family==='patient';let body=isPatient?patientHome(id):'<div class="welcome"><div class="mini-label">'+(p.family.startsWith('agency')?'PARTNER DESK':'YOUR CARE NETWORK')+'</div><strong>'+esc(p.name)+'</strong><p>Sample area · Pune & PCMC</p></div>';
    if(p.family==='hospital')body+='<h3 class="subhead">Build your care team</h3><div class="services"><button class="service wide" data-action="create" data-kind="staffing" data-actor="'+id+'">'+icon('team')+'Request ICU physician team</button></div>';
    if(p.family==='care')body+='<div class="actions"><button class="action secondary" data-page="roster" data-account="'+id+'">'+ 'View duties & request relief'+'</button></div>';
    if(p.family.startsWith('agency'))body+='<p class="hint">'+(p.family==='agency_care'?'Sai reviews applications and selects a team. The demo uses three sample physicians.':'View sample requests for your provider network. Providers accept from their own phone.')+'</p>';
    const jobs=person(id).family.startsWith('agency_')&&person(id).family!=='agency_care'?agencyJobs(id):D.visibleJobs(state,id);
    body+='<h3 class="subhead">'+(isPatient?'My requests':p.family.startsWith('agency')?'Team requests':'Requests & updates')+'</h3>';
    body+=jobs.length?jobs.map(j=>jobCard(j,id)).join(''):empty(isPatient?'Your care starts here':'Ready when you are',isPatient?'Book a service above to see the journey.':p.family==='ambulance'?'Accept transport after a hospital accepts the patient.':'Create a request on the patient or hospital phone.');
    return body;
  }
  function chat(id){
    const available=D.people.filter(p=>p.id!==id),other=partners[id]||(selected.find(x=>x!==id)||available[0].id);partners[id]=other;
    const messages=state.messages.filter(m=>(m.from===id&&m.to===other)||(m.to===id&&m.from===other));
    return '<h3 class="subhead">Care team chat</h3><label class="hint" for="recipient-'+id+'">Send a demo message to</label><select class="message-select" id="recipient-'+id+'" data-partner="'+id+'">'+available.map(p=>'<option value="'+p.id+'" '+(p.id===other?'selected':'')+'>'+esc(p.name)+'</option>').join('')+'</select><div class="chat-history">'+(messages.length?messages.map(m=>'<div class="bubble '+(m.from===id?'mine':'')+'">'+esc(m.text)+'</div>').join(''):empty('Start a conversation','Messages appear on the recipient’s Chat tab. Use fictional text only.','chat'))+'</div><form class="chat-form" data-chat="'+id+'"><input id="message-'+id+'" type="text" maxlength="300" autocomplete="off" placeholder="Type a demo message…" aria-label="Message from '+esc(name(id))+'" value="'+esc(drafts[id]||'')+'" data-draft="'+id+'"><button type="submit" class="action">Send</button></form><button class="quick-reply" data-quick="On my way for the demo visit." data-account="'+id+'">On my way</button><button class="quick-reply" data-quick="Thank you. See you soon!" data-account="'+id+'">Thank you</button><p class="hint">Sample chat stays in this page. It is not sent to real people.</p>';
  }
  function phone(id){
    const p=person(id),page=pages[id]||'home',unread=state.messages.filter(m=>m.to===id).length;
    const title=p.family==='patient'?'Hello, '+p.name:p.family==='hospital'?'Hospital control desk':p.family==='ambulance'?'Ambulance dispatch':p.family.startsWith('agency')?'Agency team desk':p.name;
    return '<section class="pane" aria-label="'+esc(p.name)+' demo screen"><div class="pane-label">'+esc(p.name)+'<button data-close="'+id+'" aria-label="Close '+esc(p.name)+' screen">×</button></div><div class="phone"><div class="phone-status"><span>9:41</span><span class="notch">'+esc(p.name)+'</span><span aria-hidden="true">▮▮ ▰</span></div><div class="phone-body" data-scroll="'+id+'"><div class="phone-top"><div><strong>'+esc(title)+'</strong><small>Fictional account · Sample area</small></div><span class="avatar">'+icon(p.icon)+'</span></div><div class="phone-content">'+(page==='chat'?chat(id):page==='roster'&&p.family==='care'?roster(id):home(id))+'</div></div><nav class="phone-nav" aria-label="'+esc(p.name)+' navigation">'+[['home','home','Home'],['chat','chat','Chat'+(unread?' · '+unread:'')],...(p.family==='care'?[['roster','calendar','Duties']]:[])].map(([key,i,label])=>'<button class="'+(page===key?'active':'')+'" data-page="'+key+'" data-account="'+id+'" aria-current="'+(page===key?'page':'false')+'">'+icon(i)+label+'</button>').join('')+'</nav><div class="home-indicator"></div></div><div class="phone-caption">'+(p.family==='patient'?'Find care. Stay connected.':p.family==='hospital'?'A connected team for every shift.':'Care, coordinated.')+'</div></section>';
  }
  function render(){
    const focused=document.activeElement,focusId=focused&&focused.id,position=focused&&focused.selectionStart;
    const scrolls={};document.querySelectorAll('[data-scroll]').forEach(el=>{scrolls[el.dataset.scroll]=el.scrollTop;});
    $('phones').innerHTML=selected.length?selected.map(phone).join(''):'<div class="empty-room">Choose screens to start your demonstration.</div>';
    document.querySelectorAll('[data-scroll]').forEach(el=>{el.scrollTop=scrolls[el.dataset.scroll]||0;});
    if(focusId&&$(focusId)){const el=$(focusId);el.focus({preventScroll:true});if(typeof position==='number'&&el.setSelectionRange)el.setSelectionRange(position,position);}
    $('status').textContent=state.notice;$('status').classList.remove('error');
    $('activity-count').textContent=state.events.length?state.events.length+' recent updates':'';
    $('activity-list').innerHTML=state.events.length?state.events.map(e=>'<li>'+esc(e.text)+'</li>').join(''):'<li>No activity yet. Start a request on a patient or hospital phone.</li>';
    picker();
  }
  function send(actionData){const outcome=D.apply(state,actionData);if(outcome.error){$('status').textContent=outcome.error;$('status').classList.add('error');return false;}state=outcome.state;render();return true;}
  document.addEventListener('click',event=>{
    const target=event.target.closest('button');if(!target)return;
    if(target.dataset.scenario){scenario=target.dataset.scenario;selected=story[scenario].accounts.slice();if(scenario==='chat')selected.forEach(id=>{pages[id]='chat';});else selected.forEach(id=>{pages[id]='home';});drawScenarios();render();}
    else if(target.dataset.close){selected=selected.filter(id=>id!==target.dataset.close);render();}
    else if(target.dataset.page){pages[target.dataset.account]=target.dataset.page;render();}
    else if(target.dataset.limit){limits[target.dataset.job]=Number(target.dataset.limit);render();}
    else if(target.dataset.quick){const id=target.dataset.account;send({type:'message',actor:id,to:partners[id],text:target.dataset.quick});}
    else if(target.dataset.action)send({type:target.dataset.action,actor:target.dataset.actor,job:target.dataset.job,kind:target.dataset.kind,candidate:target.dataset.candidate});
  });
  document.addEventListener('change',event=>{
    const target=event.target;if(target.dataset.account&&target.type==='checkbox'){const id=target.dataset.account;if(target.checked&&!selected.includes(id))selected.push(id);else if(!target.checked)selected=selected.filter(x=>x!==id);render();}
    if(target.dataset.partner){partners[target.dataset.partner]=target.value;render();}
  });
  document.addEventListener('input',event=>{if(event.target.dataset.draft)drafts[event.target.dataset.draft]=event.target.value;});
  document.addEventListener('submit',event=>{const form=event.target.closest('[data-chat]');if(!form)return;event.preventDefault();const id=form.dataset.chat,text=drafts[id]||'';if(send({type:'message',actor:id,to:partners[id],text})){drafts[id]='';render();}});
  $('choose-roles').addEventListener('click',()=>{const expanded=$('choose-roles').getAttribute('aria-expanded')==='true';$('choose-roles').setAttribute('aria-expanded',String(!expanded));$('role-picker').hidden=expanded;});
  $('columns').addEventListener('change',()=>{$('phones').className='phones columns-'+$('columns').value;});
  $('reset').addEventListener('click',()=>{state=D.initial();for(const key of Object.keys(drafts))delete drafts[key];render();});
  drawScenarios();render();
}());
