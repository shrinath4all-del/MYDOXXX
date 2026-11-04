// Reviewed add-only migration: 14 -> 36 synthetic identities. No work on import.
// Run through test-lab.cjs: expand-dry-run | expand | expand-verify.
const C=require('./common.cjs'),P=require('./test-lab-plan.cjs'),L=require('./test-lab.cjs');
const {assert,same,path,OUT,fs,sha,save,read,optional}=C;
const STATUS='test-lab-expansion-status.json',REVIEW='test-lab-expansion-review.json';
const BEFORE='test-lab-expansion-before-documents.json',CREDS='test-lab-credentials.json';
const RELEASE=`projects/${C.TARGET}/releases/cloud.firestore/${P.DATABASE}`;
const MIGRATION='roles36-v1';
function stable(v){if(Array.isArray(v))return v.map(stable);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])]));return v;}
function digest(v){return sha(JSON.stringify(stable(v)));}
function credentialIdentity(creds){return Object.fromEntries(P.LEGACY_ACCOUNTS.map(a=>{assert(creds.accounts[a.key]);return [a.key,digest(creds.accounts[a.key])];}));}
function authIdentity(users){const added=new Set(P.ADDED_ACCOUNTS.map(a=>a.uid));return users.filter(u=>!added.has(u.localId)).map(u=>({uid:u.localId,email:u.email||'',phone:u.phoneNumber||'',displayName:u.displayName||'',disabled:!!u.disabled,emailVerified:!!u.emailVerified,customAttributes:u.customAttributes||'',passwordHash:u.passwordHash||'',salt:u.salt||'',providerUserInfo:u.providerUserInfo||[]})).sort((a,b)=>a.uid.localeCompare(b.uid));}
function filteredSnapshot(snapshot,excluded=[]){const omit=new Set(excluded);return snapshot.filter(d=>!omit.has(d.path)).sort((a,b)=>a.path.localeCompare(b.path));}
// Enumerate every collection/subcollection, including missing parent documents.
// This covers user-created bookings/chat as well as the original 150 fixtures.
async function snapshotNamed(ctx){
 const found=new Map(),jobs=[{type:'parent',relative:''}],prefix=P.BASE+'/documents';
 async function process(job){
  if(job.type==='parent'){
   let pageToken;do{const resource='/'+prefix+(job.relative?'/'+job.relative:'')+':listCollectionIds';const result=(await ctx.post(resource,{pageSize:1000,...(pageToken?{pageToken}:{})})).body;for(const id of result.collectionIds||[]){assert(!id.includes('/'));jobs.push({type:'collection',relative:job.relative?job.relative+'/'+id:id});}pageToken=result.nextPageToken;}while(pageToken);
  }else{
   let pageToken;do{const resource='/'+prefix+'/'+job.relative;P.checkLabPath(resource);const result=(await ctx.firestore.get(resource,{queryParams:{pageSize:1000,showMissing:true,...(pageToken?{pageToken}:{})}})).body;for(const doc of result.documents||[]){assert(doc.name.startsWith(prefix+'/'));const relative=doc.name.slice(prefix.length+1);assert(!found.has(relative),'Duplicate document while snapshotting');if(doc.createTime||doc.updateTime||doc.fields)found.set(relative,{path:relative,fields:doc.fields||{}});jobs.push({type:'parent',relative});}pageToken=result.nextPageToken;}while(pageToken);
  }
 }
 while(jobs.length){const batch=jobs.splice(0,8);await Promise.all(batch.map(process));}
 return filteredSnapshot([...found.values()]);
}
async function target(ctx){const db=(await ctx.firestore.get('/'+P.BASE)).body;assert.equal(db.name,P.BASE);assert.equal(db.databaseEdition,'STANDARD');assert.equal(db.locationId,'nam5');assert.equal(db.type,'FIRESTORE_NATIVE');const baseline=await read(path.join(OUT,'test-lab-setup-status.json'));assert.equal(baseline.target,C.TARGET);assert.equal(baseline.databaseId,P.DATABASE);assert(baseline.complete&&baseline.seedComplete&&baseline.authComplete);same(await L.defaultRuleState(ctx.rulesApi),baseline.defaultRuleState,'Default clinical rules changed');return baseline;}
async function ruleState(ctx){const release=(await ctx.rulesApi.get('/'+RELEASE)).body;const set=(await ctx.rulesApi.get('/'+release.rulesetName)).body;const text=set.source.files.map(f=>f.content).join('\n').trim();assert([P.rules(P.LEGACY_ACCOUNTS).trim(),P.rules().trim()].includes(text),'Unexpected named test rules; refusing overwrite');return {name:release.name,rulesetName:release.rulesetName,sourceSha256:sha(text),expanded:text===P.rules().trim()};}
function statusGuard(status){assert.equal(status.target,C.TARGET);assert.equal(status.projectNumber,C.NUMBER);assert.equal(status.databaseId,P.DATABASE);assert.equal(status.migration,MIGRATION);assert.equal(status.planDigest,digest(P.expansionPlan(status.startedAt)));}
async function inspect(ctx,creds,status){
 const baseline=await target(ctx),rules=await ruleState(ctx),users=await L.listAuth(ctx.identity),byUid=new Map(users.map(u=>[u.localId,u]));
 for(const a of P.LEGACY_ACCOUNTS){const u=byUid.get(a.uid);assert(u,'Existing synthetic identity is missing');assert.equal(u.email,a.email);assert(!u.phoneNumber);assert(!u.disabled);same(JSON.parse(u.customAttributes||'{}'),P.claims(a));}
 for(const a of P.ADDED_ACCOUNTS){const u=byUid.get(a.uid);if(!u)continue;assert(status?.creationAttemptedUids?.includes(a.uid),'Added UID already exists without this migration receipt');assert.equal(u.email,a.email);assert.equal(u.displayName,a.name);assert(!u.phoneNumber);assert(!u.disabled);const claims=JSON.parse(u.customAttributes||'{}');assert(!Object.keys(claims).length||C.isDeepStrictEqual(claims,P.claims(a)),'Added identity has different claims');}
 if(status){statusGuard(status);same(credentialIdentity(creds),status.originalCredentialIdentity,'Original credentials changed');assert.equal(digest(authIdentity(users)),status.originalAuthDigest,'An existing Auth identity or password hash changed');same(await L.defaultRuleState(ctx.rulesApi),status.defaultRules,'Default rules changed');}
 else{assert.equal(Object.keys(creds.accounts).length,14,'Expanded credential file requires its migration receipt');assert(!rules.expanded,'Expanded rules require their migration receipt');}
 return {baseline,rules,users};
}
async function dryRun(){
 const ctx=await L.adminContext(),creds=await L.credentials(false),status=await optional(path.join(OUT,STATUS));
 const initial=await inspect(ctx,creds,status),startedAt=status?.startedAt||new Date().toISOString(),plan=P.expansionPlan(startedAt),snapshot=await snapshotNamed(ctx);
 const collisions=snapshot.filter(d=>plan.some(r=>r.path===d.path));assert(status||collisions.length===0,'A new fixture path is already occupied without a migration receipt');
 const result={target:C.TARGET,projectNumber:C.NUMBER,databaseId:P.DATABASE,edition:'STANDARD',location:'nam5',migration:MIGRATION,reviewedAt:new Date().toISOString(),startedAt,planDigest:digest(plan),existingAccounts:14,addedAccounts:22,totalAccounts:36,existingDocuments:snapshot.length,existingDocumentDigest:digest(snapshot),addedDocumentPaths:plan.map(r=>r.path),addedDocuments:plan.length,newUidKeys:P.ADDED_ACCOUNTS.map(a=>({key:a.key,uid:a.uid,role:a.role})),rules:{current:initial.rules.sourceSha256,next:sha(P.rules().trim()),defaultUnchanged:true,allowlistOnlyExpansion:true},existingCredentialIdentity:credentialIdentity(creds),existingAuthDigest:digest(authIdentity(initial.users)),cloudWrites:0,credentialsGenerated:false,existingProfilesOrAppointmentsOverwritten:false};
 await save(REVIEW,result);console.log(JSON.stringify({target:result.target,databaseId:P.DATABASE,edition:'STANDARD',existingSyntheticAccounts:14,newSyntheticAccounts:22,totalSyntheticAccounts:36,existingDocuments:snapshot.length,addOnlyDocuments:plan.length,cloudWrites:0,credentialsGenerated:false,reviewFile:REVIEW}));return result;
}
async function appendCredentials(creds,status){
 same(credentialIdentity(creds),status.originalCredentialIdentity);if(Object.keys(creds.accounts).length===36)return creds;
 assert.equal(Object.keys(creds.accounts).length,14);
 require('node:child_process').execFileSync('git',['-c','safe.directory='+C.ROOT,'check-ignore','--quiet','private-backups/mydoxxx-dev-261102/'+CREDS],{cwd:C.ROOT,stdio:'ignore'});
 const next=structuredClone(creds);for(const a of P.ADDED_ACCOUNTS){assert(!next.accounts[a.key]);next.accounts[a.key]={...a,password:C.crypto.randomBytes(30).toString('base64url')};}
 next.roles36Migration={id:MIGRATION,startedAt:status.startedAt};same(credentialIdentity(next),status.originalCredentialIdentity);await save(CREDS,next);return L.credentials(false);
}
async function createNewAuth(ctx,creds,status){
 const users=await L.listAuth(ctx.identity),byUid=new Map(users.map(u=>[u.localId,u]));
 for(const a of P.ADDED_ACCOUNTS){let u=byUid.get(a.uid);const secret=creds.accounts[a.key];L.checkAccount(secret);if(!u){assert(!status.complete,'Completed migration identity is missing; refusing recreation');status.creationAttemptedUids=[...new Set([...(status.creationAttemptedUids||[]),a.uid])];await save(STATUS,status);const created=(await ctx.identity.post(`/projects/${C.TARGET}/accounts`,{localId:a.uid,email:a.email,password:secret.password,displayName:a.name,emailVerified:true,disabled:false})).body;assert.equal(created.localId,a.uid);u={localId:a.uid,email:a.email,displayName:a.name};}
  assert(status.creationAttemptedUids.includes(a.uid));assert.equal(u.email,a.email);assert.equal(u.displayName,a.name);assert(!u.phoneNumber);assert(!u.disabled);const actual=JSON.parse(u.customAttributes||'{}');if(!C.isDeepStrictEqual(actual,P.claims(a))){assert.equal(Object.keys(actual).length,0,'Refusing to replace custom claims');await ctx.identity.post(`/projects/${C.TARGET}/accounts:update`,{localId:a.uid,customAttributes:JSON.stringify(P.claims(a))});}
  status.createdUids=[...new Set([...(status.createdUids||[]),a.uid])];await save(STATUS,status);
 }
 same(digest(authIdentity(await L.listAuth(ctx.identity))),status.originalAuthDigest,'Existing Auth/password fields changed');
}
async function extendRules(ctx,status){
 const current=await ruleState(ctx);if(current.expanded){status.rulesExpanded=true;await save(STATUS,status);return;}
 same(current,status.originalTestRules,'The named rule release changed after review');
 const text=P.rules(),tests=require('./test-lab-rule-check.cjs').cases();
 const compiled=(await ctx.rulesApi.post(`/projects/${C.TARGET}:test`,{source:{files:[{name:'firestore-testing.rules',content:text}]},testSuite:{testCases:tests.map(({label,...t})=>t)}})).body;
 assert(!(compiled.issues||[]).some(i=>i.severity==='ERROR'),'Expanded rules failed compilation');assert.equal(compiled.testResults?.length,tests.length);assert(compiled.testResults.every(t=>t.state==='SUCCESS'),'Expanded rules failed isolation tests');
 const set=(await ctx.rulesApi.post(`/projects/${C.TARGET}/rulesets`,{source:{files:[{name:'firestore-testing.rules',content:text}]},attachment_point:`firestore.googleapis.com/projects/${C.NUMBER}/databases/${P.DATABASE}`})).body;
 assert(set.name.startsWith(`projects/${C.TARGET}/rulesets/`));
 // Official firebase-tools gcp/rules.updateRelease payload; named DB only.
 await ctx.rulesApi.patch('/'+RELEASE,{release:{name:RELEASE,rulesetName:set.name}});
 await fs.writeFile(path.join(OUT,'firestore-testing.rules'),text);status.rulesExpanded=true;status.rulesCasesPassed=tests.length;await save(STATUS,status);
}
async function addDocuments(ctx,status){
 const plan=P.expansionPlan(status.startedAt);assert.equal(digest(plan),status.planDigest);let added=0;
 for(let start=0;start<plan.length;start+=80){const group=plan.slice(start,start+80),actual=await L.batchGet(ctx,group),writes=[];
  for(const r of group){if(actual.has(r.path)){assert((status.documentAttempts||[]).includes(r.path),'Occupied fixture has no migration write receipt');assert(actual.get(r.path).fields.mydoxSynthetic?.booleanValue===true);continue;}
   writes.push({update:{name:P.BASE+'/documents/'+r.path,fields:P.fields(r.data)},currentDocument:{exists:false}});
  }
  if(writes.length){status.documentAttempts=[...new Set([...(status.documentAttempts||[]),...writes.map(w=>w.update.name.slice((P.BASE+'/documents/').length))])];await save(STATUS,status);await ctx.post('/'+P.BASE+'/documents:commit',{writes});added+=writes.length;}
 }
 status.documentsCreatedThisRun=added;status.documentsPlanned=plan.length;status.seedAdded=true;await save(STATUS,status);
}
async function verifyExpansion(context){
 const ctx=context||await L.adminContext(),status=await read(path.join(OUT,STATUS)),creds=await L.credentials(false);statusGuard(status);assert.equal(Object.keys(creds.accounts).length,36);await inspect(ctx,creds,status);assert((await ruleState(ctx)).expanded);
 const users=await L.listAuth(ctx.identity);for(const a of P.ADDED_ACCOUNTS){const u=users.find(u=>u.localId===a.uid);assert(u);same(JSON.parse(u.customAttributes||'{}'),P.claims(a));}
 const before=await read(path.join(OUT,BEFORE)),after=await snapshotNamed(ctx),plan=P.expansionPlan(status.startedAt),filtered=filteredSnapshot(after,plan.map(r=>r.path));same(before.documents,filtered,'Existing named-database data changed; do not overwrite to repair');assert.equal(digest(filtered),status.originalDocumentDigest);
 const map=new Map(after.map(d=>[d.path,d]));for(const p of plan){assert(map.has(p.path),'An expansion fixture is missing');assert.equal(map.get(p.path).fields.mydoxSynthetic?.booleanValue,true);}
 const result={target:C.TARGET,projectNumber:C.NUMBER,databaseId:P.DATABASE,migration:MIGRATION,at:new Date().toISOString(),syntheticAccounts:36,newAccounts:22,existingCredentialsUnchanged:14,existingAuthIdentitiesAndPasswordHashesUnchanged:status.originalAuthCount,existingNamedDocumentsUnchanged:filtered.length,existingNamedDocumentDigest:status.originalDocumentDigest,addedDocuments:plan.length,totalNamedDocuments:after.length,defaultRulesUnchanged:true,onlyNamedDatabaseRulesExpanded:true,protectedProjectsModified:false,cloudRecordsWritten:0};await save('test-lab-expansion-verification.json',result);return result;
}
async function expand(){
 const ctx=await L.adminContext();let creds=await L.credentials(false),status=await optional(path.join(OUT,STATUS));const checked=await inspect(ctx,creds,status);
 if(!status){const review=await read(path.join(OUT,REVIEW));assert.equal(review.target,C.TARGET);assert.equal(review.projectNumber,C.NUMBER);assert.equal(review.databaseId,P.DATABASE);assert.equal(review.migration,MIGRATION);assert(Date.now()-Date.parse(review.reviewedAt)<24*3600000,'Run expand-dry-run again; review is older than 24h');const snapshot=await snapshotNamed(ctx);assert.equal(digest(snapshot),review.existingDocumentDigest,'Test data changed since dry run; refresh review with test panels idle');same(credentialIdentity(creds),review.existingCredentialIdentity);assert.equal(digest(authIdentity(checked.users)),review.existingAuthDigest);assert.equal(digest(P.expansionPlan(review.startedAt)),review.planDigest);
  status={target:C.TARGET,projectNumber:C.NUMBER,databaseId:P.DATABASE,migration:MIGRATION,startedAt:review.startedAt,planDigest:review.planDigest,originalCredentialIdentity:credentialIdentity(creds),originalAuthDigest:digest(authIdentity(checked.users)),originalAuthCount:authIdentity(checked.users).length,originalDocumentDigest:digest(snapshot),originalDocumentCount:snapshot.length,originalTestRules:checked.rules,defaultRules:await L.defaultRuleState(ctx.rulesApi),creationAttemptedUids:[],createdUids:[],documentAttempts:[],complete:false};
  await save(BEFORE,{target:C.TARGET,databaseId:P.DATABASE,at:new Date().toISOString(),documents:snapshot});await save(STATUS,status);
 }
 statusGuard(status);if(status.complete){console.log(JSON.stringify(await verifyExpansion(ctx)));return;}
 creds=await appendCredentials(creds,status);await createNewAuth(ctx,creds,status);await addDocuments(ctx,status);await extendRules(ctx,status);const result=await verifyExpansion(ctx);status.complete=true;status.completedAt=new Date().toISOString();await save(STATUS,status);console.log(JSON.stringify({...result,mutationCompleted:true}));
}
async function main(action){if(action==='expand-dry-run')await dryRun();else if(action==='expand')await expand();else if(action==='expand-verify')console.log(JSON.stringify(await verifyExpansion()));else throw Error('Unknown expansion action');}
module.exports={main,stable,digest,credentialIdentity,authIdentity,filteredSnapshot,snapshotNamed,statusGuard};
