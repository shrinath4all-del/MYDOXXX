const C=require('../common.cjs'),path=require('node:path');
const DATABASE='mydoxxx-testing';
async function main(){
 C.assert(process.argv.includes('--apply'),'Explicit --apply required');
 const s=await C.session(),rules=s.api('firebaserules.googleapis.com','v1');
 const base='/projects/'+C.TARGET;
 const db=(await s.api('firestore.googleapis.com','v1').get(base+'/databases/'+DATABASE)).body;
 C.assert.equal(db.databaseEdition,'STANDARD');
 const defaultBefore=(await rules.get(base+'/releases/cloud.firestore')).body;
 const release=base+'/releases/cloud.firestore/'+DATABASE;
 const before=(await rules.get(release)).body;
 const oldSet=(await rules.get('/'+before.rulesetName)).body;
 const oldSource=oldSet.source.files.map(f=>f.content).join('\n');
 const legacy=await C.fs.readFile(path.join(C.OUT,'firestore-testing.rules'),'utf8');
 const source=await C.fs.readFile(path.join(C.ROOT,'experiments/MYDOXXX/cloud-test-room-rules/firestore.rules'),'utf8');
 C.assert(oldSource.trim()===legacy.trim()||oldSource.trim()===source.trim(),'Named rules changed concurrently; review before overwrite');
 const report=await C.read(path.join(C.OUT,'cloud-test-room-rule-test.json'));
 C.assert(!report.issues?.some(i=>i.severity==='ERROR'),'Rule test errors');
 C.assert(source.includes('validCloudWindow()')&&source.includes("database == 'mydoxxx-testing'"));
 let next=before;
 if(oldSource.trim()!==source.trim()){
   const compiled=(await rules.post(base+':test',{source:{files:[{name:'firestore.rules',content:source}]}})).body;
   C.assert(!(compiled.issues||[]).some(i=>i.severity==='ERROR'),'Rules did not compile');
   const set=(await rules.post(base+'/rulesets',{source:{files:[{name:'firestore.rules',content:source}]},attachment_point:`firestore.googleapis.com/projects/${C.NUMBER}/databases/${DATABASE}`})).body;
   C.assert.equal((await rules.get(release)).body.rulesetName,before.rulesetName,'Concurrent rule update detected');
   next=(await rules.patch(release,{release:{name:release.slice(1),rulesetName:set.name},updateMask:'rulesetName'})).body;
 }
 const final=(await rules.get(release)).body;
 const finalSet=(await rules.get('/'+final.rulesetName)).body;
 C.same(finalSet.source.files.map(f=>f.content).join('\n').trim(),source.trim(),'Published rule readback mismatch');
 C.assert.equal((await rules.get(base+'/releases/cloud.firestore')).body.rulesetName,defaultBefore.rulesetName,'Default rules must remain unchanged');
 const receipt={project:C.TARGET,database:DATABASE,previousRuleset:before.rulesetName,ruleset:final.rulesetName,sourceSha256:C.sha(source),defaultDatabaseUnchanged:true,localLoginsPreserved:true,cloudMaximumHours:8,completedAt:new Date().toISOString()};
 await C.save('cloud-test-room-rules-deployed.json',receipt);console.log(JSON.stringify(receipt));
}
main().catch(e=>{console.error('Cloud rule deployment stopped: '+e.message);process.exitCode=1;});
