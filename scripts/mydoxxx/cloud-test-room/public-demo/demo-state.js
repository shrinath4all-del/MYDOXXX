(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.BfastDemo = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const families = [
    ['patient','Patient','Patients','heart'],['doctor','Cardiologist','Cardiologists','doctor'],
    ['hospital','Hospital','Hospitals','hospital'],['ambulance','Ambulance','Ambulances','ambulance'],
    ['care','Care physician','Care physicians','doctor'],['nurse','Nurse','Nurses','nurse'],
    ['technician','Technician','Technicians','lab'],['physio','Physiotherapist','Physiotherapists','activity'],
    ['agency_care','Sai care agency','Sai care agencies','team'],['agency_nurse','Nursing agency','Nursing agencies','team'],
    ['agency_tech','Technician agency','Technician agencies','team'],['agency_physio','Physio agency','Physio agencies','team']
  ].map(([key,label,plural,icon])=>({key,label,plural,icon}));
  const people = families.flatMap(f => [1,2,3].map(n => ({id:f.key+'-'+n,family:f.key,number:n,name:f.label+' '+n,icon:f.icon,score:[94,88,81][n-1]})));
  const byId = Object.fromEntries(people.map(p=>[p.id,p]));
  const clone = value => JSON.parse(JSON.stringify(value));
  const roles = family => people.filter(p=>p.family===family).map(p=>p.id);
  const initial = () => ({sequence:0,jobs:[],messages:[],events:[],leave:[],notice:'Choose a scenario, then follow the steps across the phones.'});
  function result(state,message){return {state,error:message};}
  function apply(previous, action) {
    if (!action || !byId[action.actor]) return result(previous,'Choose a valid demo account.');
    const state=clone(previous), actor=byId[action.actor];
    function fail(message){return result(previous,message);}
    function event(text){state.events.unshift({id:++state.sequence,text});state.events=state.events.slice(0,16);state.notice=text;}
    function jobById(){return state.jobs.find(j=>j.id===action.job);}
    const name=id=>byId[id].name;
    if(action.type==='create'){
      const kind=action.kind;
      const mapping={consultation:'doctor',nursing:'nurse',lab:'technician',physio:'physio',emergency:'hospital',staffing:'care'};
      if(!mapping[kind])return fail('Unknown demonstration service.');
      if(kind==='staffing'?actor.family!=='hospital':actor.family!=='patient')return fail('This account cannot create that request.');
      if(state.jobs.some(j=>j.owner===actor.id&&j.kind===kind&&j.status!=='completed'))return fail('This account already has an active request for this service.');
      const title={consultation:'Cardiology consultation',nursing:'Home nursing visit',lab:'Home sample collection',physio:'Physiotherapy at home',emergency:'Emergency care coordination',staffing:'ICU care physician team'}[kind];
      const job={id:'request-'+(++state.sequence),kind,title,owner:actor.id,status:kind==='staffing'?'applications':'pending',candidates:roles(mapping[kind]),declined:[],assigned:null,hospital:null,doctor:null,ambulance:null,applicants:[],selected:[],stage:kind==='emergency'?'hospital':'request'};
      state.jobs.unshift(job);event(name(actor.id)+' requested '+title.toLowerCase()+'.');
    }else if(action.type==='accept'||action.type==='decline'){
      const j=jobById();if(!j)return fail('Request not found.');
      if(j.kind==='staffing')return fail('Apply to a staffing request; Sai selects the team.');
      let target=j.candidates;
      if(j.kind==='emergency'){
        if(j.stage==='hospital')target=roles('hospital');
        else if(j.stage==='team')target=actor.family==='doctor'?roles('doctor'):actor.family==='ambulance'?roles('ambulance'):[];
        else return fail('This emergency is already covered.');
      }
      if(!target.includes(actor.id)||j.declined.includes(actor.id))return fail('This request is not available to this account.');
      if(j.status==='completed')return fail('This request is complete.');
      if(j.kind==='emergency'){
        const slot=j.stage==='hospital'?'hospital':actor.family;
        if(j[slot])return fail('Another provider has already accepted this part.');
        if(action.type==='decline'){j.declined.push(actor.id);event(name(actor.id)+' declined. Other eligible demo providers can accept.');}
        else {j[slot]=actor.id;if(slot==='hospital'){j.stage='team';j.status='coordinating';}if(j.doctor&&j.ambulance){j.stage='covered';j.status='accepted';}event(name(actor.id)+' accepted the emergency '+(slot==='hospital'?'hospital request':slot==='doctor'?'doctor request':'transport request')+'.');}
      }else{
        if(j.assigned||j.status!=='pending')return fail('Another provider has already accepted this request.');
        if(action.type==='decline'){j.declined.push(actor.id);event(name(actor.id)+' declined. The request remains available to others.');}
        else{j.assigned=actor.id;j.status='accepted';event(name(actor.id)+' accepted '+j.title.toLowerCase()+'.');}
      }
    }else if(action.type==='complete'){
      const j=jobById();if(!j)return fail('Request not found.');
      if(j.status!=='accepted')return fail('Finish arranging care before completing this demo request.');
      if(actor.id!==j.owner&&actor.id!==j.assigned&&actor.id!==j.hospital)return fail('Only the requester or assigned provider can complete it.');
      j.status='completed';event(j.title+' completed in the demo.');
    }else if(action.type==='apply'){
      const j=jobById();if(!j||j.kind!=='staffing'||j.status!=='applications')return fail('Applications are closed.');
      if(actor.family!=='care'||!j.candidates.includes(actor.id))return fail('Only eligible care physicians can apply.');
      if(j.applicants.includes(actor.id))return fail('You have already applied.');
      j.applicants.push(actor.id);event(name(actor.id)+' applied for the ICU team.');
    }else if(action.type==='select'){
      const j=jobById();if(!j||j.kind!=='staffing'||j.status!=='applications')return fail('This staffing request is closed.');
      if(actor.id!=='agency_care-1')return fail('Sai care agency 1 manages this sample hospital request.');
      if(!j.applicants.includes(action.candidate))return fail('Select a physician who has applied.');
      if(j.selected.includes(action.candidate))return fail('This physician is already selected.');
      j.selected.push(action.candidate);if(j.selected.length===3)j.status='accepted';event('Sai selected '+name(action.candidate)+' for the sample ICU team.');
    }else if(action.type==='leave'){
      if(actor.family!=='care')return fail('Only care physicians use this sample roster.');
      if(state.leave.some(l=>l.owner===actor.id&&l.status!=='covered'))return fail('You already have a relief request.');
      const l={id:'leave-'+(++state.sequence),owner:actor.id,status:'pending',replacement:null};state.leave.push(l);
      const j={id:'request-'+(++state.sequence),kind:'relief',title:'Roster relief · tomorrow',owner:actor.id,status:'pending',candidates:roles('care').filter(id=>id!==actor.id),declined:[],assigned:null,leaveId:l.id};state.jobs.unshift(j);event(name(actor.id)+' requested relief. Other care physicians can accept.');
    }else if(action.type==='message'){
      if(!byId[action.to]||action.to===actor.id)return fail('Choose another demo account.');
      if(typeof action.text!=='string'||!action.text.trim()||action.text.length>300)return fail('Write a message of 1–300 characters.');
      state.messages.push({id:++state.sequence,from:actor.id,to:action.to,text:action.text.trim()});state.messages=state.messages.slice(-120);event(name(actor.id)+' sent a demo message to '+name(action.to)+'.');
    }else return fail('Unknown demo action.');
    for(const j of state.jobs)if(j.kind==='relief'&&j.assigned){const l=state.leave.find(x=>x.id===j.leaveId);if(l){l.status='covered';l.replacement=j.assigned;}}
    return {state,error:null};
  }
  function visibleJobs(state,id){const p=byId[id];if(!p)return [];return state.jobs.filter(j=>j.owner===id||j.assigned===id||j.selected?.includes(id)||j.candidates?.includes(id)||j.hospital===id||j.doctor===id||j.ambulance===id||(j.kind==='emergency'&&j.stage!=='hospital'&&['doctor','ambulance'].includes(p.family))||(j.kind==='staffing'&&id==='agency_care-1')||(j.kind==='relief'&&id==='agency_care-1'));}
  function ranking(job){return (job.applicants||[]).map(id=>byId[id]).sort((a,b)=>b.score-a.score||a.id.localeCompare(b.id));}
  return {families,people,byId,roles,initial,apply,visibleJobs,ranking};
}));
