// Local-only checks. This script never authenticates or calls a cloud API.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const ROOT=path.resolve(__dirname,'..'),TARGET='mydoxxx-dev-261102';
const expected=['48df0170','bb9ed54e','7dd56ad3'];
function json(p){return JSON.parse(fs.readFileSync(path.join(ROOT,p),'utf8').replace(/^\uFEFF/,''));}
try{
 const rc=json('.firebaserc'),config=json('firebase.json');
 assert.deepEqual(rc.projects,{default:TARGET},'The Firebase alias must point only to the experiment');
 assert.equal(config.functions.length,3);let total=0;
 for(const suffix of expected){
  const fn=config.functions.find(f=>f.source==='functions/group-'+suffix);
  assert(fn,'Expected function group missing');assert.equal(fn.codebase,'experiment-'+suffix);assert.equal(fn.runtime,'nodejs22');
  const folder=path.resolve(ROOT,fn.source);assert(folder.startsWith(ROOT+path.sep),'Function path escapes this repository');
  const pkg=json(fn.source+'/package.json');assert.equal(pkg.main,'index.js');assert.equal(pkg.engines.node,'22');
  const code=fs.readFileSync(path.join(folder,'index.js'),'utf8');
  assert(code.includes("const EXPECTED_PROJECT='"+TARGET+"'"),'Function project guard differs');
  assert(code.includes("process.env.MYDOX_RECOVERY_MODE!=='false'"),'Recovery guard missing');
  assert(code.includes('runtimeProject()!==EXPECTED_PROJECT'),'Runtime target guard missing');
  assert(code.includes('wrapped.__endpoint.minInstances=0'));assert(code.includes('wrapped.__endpoint.maxInstances=1'));
  assert(code.includes("invoker=['private']"));assert(code.includes('wrapped.run=wrapped'));
  assert(code.includes('delete wrapped.__endpoint.scheduleTrigger'));assert(code.includes('delete wrapped.__endpoint.callableTrigger'));
  const match=code.match(/const allow=(\[[^;]+\]);/);assert(match,'Function allowlist missing');total+=JSON.parse(match[1]).length;
  const envFiles=fs.readdirSync(folder).filter(f=>f.startsWith('.env'));
  assert.deepEqual(envFiles,['.env.'+TARGET],'Unexpected environment file');
  assert.equal(fs.readFileSync(path.join(folder,envFiles[0]),'utf8').trim(),'MYDOX_RECOVERY_MODE=true','Recovery environment has changed');
 }
 assert.equal(total,36,'Expected 36 guarded handlers');
 for(const name of ['firestore.rules','storage.rules']){const rules=fs.readFileSync(path.join(ROOT,name),'utf8');assert(rules.includes('if false'),'Recovery rules must remain closed');assert(!rules.includes('if true'),'Open access rule detected');}
 let matched=0;
 if(process.argv.includes('--baseline')){
  for(const item of json('SOURCE-MANIFEST.json').copiedFiles){
   const file=path.resolve(ROOT,item.file);assert(file.startsWith(ROOT+path.sep));
   const digest=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');assert.equal(digest,item.sha256,'Baseline file changed: '+item.file);matched++;
  }
 }
 console.log(JSON.stringify({project:TARGET,sourceGroups:3,guardedHandlers:total,localChecksPassed:true,baselineFilesVerified:matched,cloudCalls:false}));
}catch(error){console.error('MYDOXXX isolation check failed: '+error.message);process.exitCode=1;}

