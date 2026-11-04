// MYDOXXX-only recovery staging. Original business handlers remain in original-index.js.
const EXPECTED_PROJECT='mydoxxx-dev-261102';
function runtimeProject(){
  const direct=process.env.GCLOUD_PROJECT||process.env.GCP_PROJECT;
  if(direct)return direct;
  try{return JSON.parse(process.env.FIREBASE_CONFIG||'{}').projectId;}catch{return undefined;}
}
if(runtimeProject()&&runtimeProject()!==EXPECTED_PROJECT)throw Error('MYDOXXX function package refused a different Firebase project');
const original=require('./original-index');
const allow=["careShiftSweep", "notifyAppointment", "notifyCareShift", "notifyChatMessage", "notifyDutyTeam", "notifyIncomingCall", "notifyJobInterest", "notifyNurseDutyTeam", "notifyNurseJobInterest", "notifyNurseShift", "notifyNurseTeamRequest", "notifyTeamRequest", "notifyTechnicianDutyRequest", "notifyTechnicianDutyTeam", "notifyTechnicianJobInterest", "notifyTechnicianShift", "notifyTechnicianTeamRequest", "nurseShiftSweep", "technicianShiftSweep", "widenRequestSearch"];
for(const name of allow){
  const handler=original[name];
  if(typeof handler!=='function')throw Error('Missing recovered export: '+name);
  const wrapped=function(...args){
    if(runtimeProject()!==EXPECTED_PROJECT||process.env.MYDOX_RECOVERY_MODE!=='false'){
      const response=args[1];
      if(response&&typeof response.status==='function')return response.status(503).json({error:{status:'UNAVAILABLE',message:'MYDOXXX experimental backend is not activated.'}});
      return Promise.resolve();
    }
    return handler(...args);
  };
  Object.assign(wrapped,handler);
  if(handler.__endpoint){
    wrapped.__endpoint=JSON.parse(JSON.stringify(handler.__endpoint));
    wrapped.__endpoint.minInstances=0;
    wrapped.__endpoint.maxInstances=1;
    // Stage original callables and schedules as private HTTP endpoints so Firebase
    // does not expose them publicly or create recurring jobs during recovery.
    if(wrapped.__endpoint.callableTrigger||wrapped.__endpoint.scheduleTrigger){
      delete wrapped.__endpoint.callableTrigger;
      delete wrapped.__endpoint.scheduleTrigger;
      wrapped.__endpoint.httpsTrigger={invoker:['private']};
    }
    if(wrapped.__endpoint.httpsTrigger)wrapped.__endpoint.httpsTrigger.invoker=['private'];
  }
  wrapped.run=wrapped;
  exports[name]=wrapped;
}
