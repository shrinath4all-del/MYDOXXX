// Dependencies must be installed in each group first. These are local inert-handler tests.
const assert=require('node:assert/strict'),path=require('node:path'),{spawnSync}=require('node:child_process');
const groups=['48df0170','bb9ed54e','7dd56ad3'],ROOT=path.resolve(__dirname,'..'),TARGET='mydoxxx-dev-261102';
async function main(){
 const group=process.argv[2];
 if(!group){for(const g of groups){const child=spawnSync(process.execPath,[__filename,g],{stdio:'inherit'});assert.equal(child.status,0,'Guard checks failed for '+g);}return;}
 assert(groups.includes(group));process.env.GCLOUD_PROJECT=TARGET;process.env.MYDOX_RECOVERY_MODE='true';
 process.env.FIREBASE_CONFIG=JSON.stringify({projectId:TARGET,storageBucket:TARGET+'.firebasestorage.app'});
 const handlers=require(path.join(ROOT,'functions/group-'+group));let http=0,event=0;
 for(const fn of Object.values(handlers)){
  assert.equal(fn.__endpoint.minInstances,0);assert.equal(fn.__endpoint.maxInstances,1);assert.equal(fn.run,fn);
  assert(!fn.__endpoint.scheduleTrigger);assert(!fn.__endpoint.callableTrigger);
  if(fn.__endpoint.httpsTrigger){assert.deepEqual(fn.__endpoint.httpsTrigger.invoker,['private']);let replies=0;await fn({}, {status(c){assert.equal(c,503);return this;},json(x){assert.equal(x.error.status,'UNAVAILABLE');replies++;}});assert.equal(replies,1);http++;}
  else{assert(fn.__endpoint.eventTrigger);await fn({});event++;}
 }
 process.env.MYDOX_RECOVERY_MODE='false';
 for(const wrong of ['mydox-be432','mydox-shrinath-backup-261102','clinigo-77808','mydoxxx']){
  process.env.GCLOUD_PROJECT=wrong;
  for(const fn of Object.values(handlers)){if(fn.__endpoint.httpsTrigger){let rejected=0;await fn({}, {status(c){assert.equal(c,503);return this;},json(){rejected++;}});assert.equal(rejected,1);}else await fn({});}
 }
 console.log(JSON.stringify({group,handlers:http+event,privateHttp:http,guardedEvent:event,protectedProjectsRejected:4,sideEffects:false}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});

