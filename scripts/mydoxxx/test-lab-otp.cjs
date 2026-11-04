// Existing synthetic SERVICE codes only. Never Firebase Auth/SMS OTPs.
// Importing is inert. Commands: review | apply | verify.
const C=require('./common.cjs'),P=require('./test-lab-plan.cjs'),L=require('./test-lab.cjs');
const E=require('./test-lab-expand.cjs');
const REVIEW='test-lab-otp-review.json',DONE='test-lab-otp-verification.json',APPLIED='test-lab-otp-applied.json';
const CODE='7777',VERSION='service-otp-7777-v1';
const ALLOWED=Object.freeze({appointments:['otp','ambulanceOtp','hospitalOtp','doctorOtp'],shifts:['arrivalOtp'],nurse_shifts:['arrivalOtp'],technician_shifts:['arrivalOtp']});
const ACTOR_FIELDS=new Set(['patientUid','doctorUid','hospitalUid','ambulanceUid','assignedDoctorUid','assignedHospitalUid','assignedAmbulanceUid','carePhysicianUid','nurseUid','technicianUid','therapistUid','providerUid','userUid','agencyId','posterId','claimedBy']);
const UID_MAP=new Map(P.ACCOUNTS.map(a=>[a.uid,a]));
function walk(fields,visitor,prefix=[]){for(const [key,v] of Object.entries(fields||{})){const segments=[...prefix,key];visitor(key,v,segments);if(v.mapValue)walk(v.mapValue.fields,visitor,segments);if(v.arrayValue)for(const [i,x] of (v.arrayValue.values||[]).entries()){const at=[...segments,String(i)];visitor('',x,at);if(x.mapValue)walk(x.mapValue.fields,visitor,at);}}}
function codeFields(fields){const found=[];walk(fields,(key,value,segments)=>{if(/otp$/i.test(key))found.push({key,value,segments});});return found;}
function text(v){return v?.stringValue||'';}
function participantGuard(path,fields,knownPaths){
 const parts=path.split('/');C.assert.equal(parts.length,2,'OTP record must be a top-level service document');C.assert(Object.hasOwn(ALLOWED,parts[0]),'OTP document collection is not approved');C.assert(parts[1]&&!parts[1].includes('%'),'Invalid service document id');
 const participants=[];
 walk(fields,(key,v)=>{
  if(v.referenceValue){const prefix=P.BASE+'/documents/';C.assert(v.referenceValue.startsWith(prefix),'Foreign database reference refused');C.assert(knownPaths.has(v.referenceValue.slice(prefix.length)),'Unknown document reference refused');}
  if(ACTOR_FIELDS.has(key)||/Uid$/.test(key)){
   C.assert(v.stringValue!==undefined||v.nullValue!==undefined,'Unexpected participant field type');const uid=text(v);if(uid){C.assert(UID_MAP.has(uid)&&uid.startsWith('mdxtest'),'Unknown or non-synthetic participant refused');participants.push(uid);}
  }
  if(/Uids$/.test(key)){C.assert(v.arrayValue,'Unexpected participant list type');for(const x of v.arrayValue.values||[]){C.assert(UID_MAP.has(text(x)),'Unknown participant in list');participants.push(text(x));}}
 });
 if(parts[0]==='appointments')C.assert(['patient','hospital'].includes(UID_MAP.get(text(fields.patientUid))?.role),'Appointment must belong to a synthetic patient/hospital');
 else{
  C.assert(['hospital','agency'].includes(UID_MAP.get(text(fields.posterId))?.role),'Shift must belong to a synthetic hospital/agency');
  const expected={shifts:'care_physician',nurse_shifts:'nurse',technician_shifts:'technician'}[parts[0]];
  C.assert.equal(UID_MAP.get(text(fields.claimedBy))?.role,expected,'Arrival OTP must belong to its synthetic claimed provider');
 }
 C.assert(participants.length>0,'No synthetic participant in service record');return [...new Set(participants)].sort();
}
function patchFor(path,fields,knownPaths){
 const list=codeFields(fields);if(!list.length)return null;
 const permitted=ALLOWED[path.split('/')[0]];C.assert(permitted,'Unrecognized OTP-bearing document collection; review separately');
 const participants=participantGuard(path,fields,knownPaths),patch={},ignored=[];
 for(const item of list){C.assert.equal(item.segments.length,1,'Nested OTP field is not approved by the app schema');C.assert(permitted.includes(item.key),'Unknown OTP code field refused');
  if(item.value.nullValue!==undefined||item.value.stringValue===''){ignored.push(item.key);continue;}
  const old=item.value.stringValue??item.value.integerValue;C.assert(typeof old==='string'&&/^\d{4}$/.test(old),'Unexpected non-four-digit service OTP refused');
  // Preserve existing scalar type. Do not create absent/unissued codes.
  const next=item.value.stringValue!==undefined?{stringValue:CODE}:{integerValue:CODE};if(!C.isDeepStrictEqual(item.value,next))patch[item.key]=next;
 }
 return {patch,participants,existingCodeFields:list.map(x=>x.key).sort(),ignoredUnissuedFields:ignored.sort()};
}
async function context(){const ctx=await L.adminContext(),db=(await ctx.firestore.get('/'+P.BASE)).body;C.assert.equal(C.TARGET,'mydoxxx-dev-261102');C.assert.equal(C.NUMBER,'724915428929');C.assert.equal(P.DATABASE,'mydoxxx-testing');C.assert.equal(db.name,P.BASE);C.assert.equal(db.databaseEdition,'STANDARD');C.assert.equal(db.locationId,'nam5');
 const users=await L.listAuth(ctx.identity);for(const a of P.ACCOUNTS){const user=users.find(u=>u.localId===a.uid);C.assert(user&&!user.disabled&&!user.phoneNumber,'Synthetic Auth account guard failed');C.assert.equal(user.email,a.email);C.same(JSON.parse(user.customAttributes||'{}'),P.claims(a),'Synthetic server claims differ');}
 const defaultRules=await L.defaultRuleState(ctx.rulesApi);return {ctx,defaultRules,authFingerprint:E.digest(users.map(u=>({uid:u.localId,email:u.email||'',phone:u.phoneNumber||'',disabled:!!u.disabled,customAttributes:u.customAttributes||'',passwordHash:u.passwordHash||'',salt:u.salt||''})).sort((a,b)=>a.uid.localeCompare(b.uid)))};
}
async function inspect(ctx){
 const snapshot=await E.snapshotNamed(ctx),known=new Set(snapshot.map(x=>x.path)),candidates=[];let alreadyFixed=0,unissued=0;
 for(const record of snapshot){const result=patchFor(record.path,record.fields,known);if(!result)continue;unissued+=result.ignoredUnissuedFields.length;if(Object.keys(result.patch).length)candidates.push({path:record.path,...result});else alreadyFixed+=result.existingCodeFields.length-result.ignoredUnissuedFields.length;}
 const actual=candidates.length?await L.batchGet(ctx,candidates):new Map();
 const plan=candidates.map(item=>{const doc=actual.get(item.path);C.assert(doc&&doc.updateTime,'OTP candidate disappeared');const fresh=patchFor(item.path,doc.fields,known);C.same(fresh,itemForValidation(item),'OTP candidate changed during review');return {...item,before:doc.fields,updateTime:doc.updateTime};});
 return {snapshot,known,plan,alreadyFixed,unissued};
}
function itemForValidation(item){const {path,...rest}=item;return rest;}
function summary(plan){const counts={};for(const item of plan)for(const key of Object.keys(item.patch)){const group=item.path.split('/')[0]+'.'+key;counts[group]=(counts[group]||0)+1;}return counts;}
function validateReview(review){C.assert.equal(review.target,C.TARGET);C.assert.equal(review.projectNumber,C.NUMBER);C.assert.equal(review.databaseId,P.DATABASE);C.assert.equal(review.version,VERSION);C.assert.equal(review.code,CODE);C.assert.equal(review.planDigest,E.digest(review.plan));const known=new Set(review.snapshot.map(r=>r.path));for(const item of review.plan){const expected=patchFor(item.path,item.before,known);C.same(item.patch,expected.patch);C.same(item.participants,expected.participants);C.assert(typeof item.updateTime==='string'&&item.updateTime.length>0);}return known;}
function expectedDocuments(review){const patches=new Map(review.plan.map(x=>[x.path,x.patch]));return review.snapshot.map(r=>({path:r.path,fields:{...r.fields,...(patches.get(r.path)||{})}}));}
async function verify(ctx,review,guard){
 validateReview(review);C.same(guard.defaultRules,review.defaultRules,'Default rules changed');C.assert.equal(guard.authFingerprint,review.authFingerprint,'Auth/password state changed');const after=await E.snapshotNamed(ctx),expected=expectedDocuments(review);C.same(after,expected,'Database changed outside the reviewed OTP fields; do not overwrite');
 const result={target:C.TARGET,projectNumber:C.NUMBER,databaseId:P.DATABASE,version:VERSION,at:new Date().toISOString(),serviceCode:CODE,verifiedDocuments:review.plan.length,changedCodeFields:summary(review.plan),totalNamedDocuments:after.length,nonOtpFieldsUnchanged:true,authAndPasswordsUnchanged:true,defaultRulesUnchanged:true,defaultDatabaseWrites:0,protectedProjectsModified:false,attemptsLocksExpiryStatusPaymentGpsUntouched:true};await C.save(DONE,result);return result;
}
async function main(action=process.argv[2]){
 C.assert(['review','apply','verify'].includes(action),'Use review | apply | verify');const guard=await context(),ctx=guard.ctx;
 if(action==='review'){
  const inspected=await inspect(ctx);C.assert(inspected.plan.length<=400,'Too many records for one atomic reviewed commit');const at=new Date().toISOString();const review={target:C.TARGET,projectNumber:C.NUMBER,databaseId:P.DATABASE,version:VERSION,code:CODE,at,defaultRules:guard.defaultRules,authFingerprint:guard.authFingerprint,snapshot:inspected.snapshot,plan:inspected.plan,planDigest:E.digest(inspected.plan)};
  await C.save(REVIEW,review);console.log(JSON.stringify({target:C.TARGET,databaseId:P.DATABASE,edition:'STANDARD',scannedDocuments:inspected.snapshot.length,documentsToUpdate:inspected.plan.length,codeFieldsToUpdate:summary(inspected.plan),alreadyFixedFields:inspected.alreadyFixed,unissuedFieldsUntouched:inspected.unissued,cloudWrites:0,privateReviewFile:REVIEW}));return;
 }
 const review=await C.read(C.path.join(C.OUT,REVIEW));validateReview(review);
 if(action==='apply'){
  C.assert(Date.now()-Date.parse(review.at)<3600000,'Review is older than one hour; refresh before applying');const applied=await C.optional(C.path.join(C.OUT,APPLIED));if(applied?.planDigest===review.planDigest){console.log(JSON.stringify(await verify(ctx,review,guard)));return;}
  const now=await inspect(ctx);C.same(now.snapshot,review.snapshot,'Database changed since OTP review; refresh review without overwriting');C.same(now.plan,review.plan,'OTP records/timestamps changed since review');C.same(guard.defaultRules,review.defaultRules);C.assert.equal(guard.authFingerprint,review.authFingerprint);
  const writes=review.plan.map(r=>({update:{name:P.BASE+'/documents/'+r.path,fields:r.patch},updateMask:{fieldPaths:Object.keys(r.patch)},currentDocument:{updateTime:r.updateTime}}));
  const response=writes.length?(await ctx.post('/'+P.BASE+'/documents:commit',{writes})).body:{writeResults:[]};C.assert.equal(response.writeResults.length,writes.length);
  // Private rollback data only. Never auto-rollback: use these exact OTP masks
  // with the post-write updateTime and fresh review to preserve later changes.
  await C.save(APPLIED,{target:C.TARGET,projectNumber:C.NUMBER,databaseId:P.DATABASE,version:VERSION,at:new Date().toISOString(),planDigest:review.planDigest,commitTime:response.commitTime||null,rollback:review.plan.map((r,i)=>({path:r.path,fieldMask:Object.keys(r.patch),originalOtpFields:Object.fromEntries(Object.keys(r.patch).map(k=>[k,r.before[k]])),requireCurrentUpdateTime:response.writeResults[i].updateTime}))});
 }
 console.log(JSON.stringify(await verify(ctx,review,guard)));
}
if(require.main===module)main().catch(e=>{console.error(e.code==='ERR_ASSERTION'?e.message:'Synthetic service OTP operation stopped; no credentials or record contents printed.');process.exitCode=1;});
module.exports={ALLOWED,CODE,patchFor,participantGuard,codeFields,walk,summary,validateReview,expectedDocuments};
