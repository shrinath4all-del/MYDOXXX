// Destination-only data recovery utilities. No APIs run merely by importing this file.
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict'),{isDeepStrictEqual}=require('node:util');
const ROOT=path.resolve(__dirname,'../..');
const TARGET='mydoxxx-dev-261102',NUMBER='724915428929',OWNER='shrinath4all@gmail.com';
const PROTECTED=Object.freeze(['mydox-be432','mydox-shrinath-backup-261102','clinigo-77808','mydoxxx']);
const SOURCE=path.join(ROOT,'private-backups/mydox-be432-2026-11-02');
const OUT=path.join(ROOT,'private-backups/mydoxxx-dev-261102');
const RECOVERY=path.join(ROOT,'private-backups/mydox-shrinath-backup-261102');
const BUCKET=TARGET+'.firebasestorage.app';
const SRC_BASE='projects/mydox-be432/databases/(default)/documents';
const DST_BASE=`projects/${TARGET}/databases/(default)/documents`;
const CLI='C:/Users/Lenovo/AppData/Local/npm-cache/_npx/ba4f1959e38407b5/node_modules/firebase-tools/lib';
function sha(data){return crypto.createHash('sha256').update(data).digest('hex');}
function same(a,b,message){assert(isDeepStrictEqual(a,b),message);}
async function read(file){return JSON.parse((await fs.readFile(file,'utf8')).replace(/^\uFEFF/,''));}
async function optional(file){try{return await read(file);}catch(e){if(e.code==='ENOENT')return null;throw e;}}
async function save(name,data){assert(!name.includes('/')&&!name.includes('\\'),'Receipt name must be a filename');await fs.mkdir(OUT,{recursive:true});const destination=path.join(OUT,name),temporary=destination+'.tmp';await fs.writeFile(temporary,JSON.stringify(data,null,2));await fs.rename(temporary,destination);}
function assertTarget(){assert.equal(TARGET,'mydoxxx-dev-261102');assert.equal(NUMBER,'724915428929','MYDOXXX project number does not match the verified new project');assert(!PROTECTED.includes(TARGET));assert.equal(OUT,path.join(ROOT,'private-backups/mydoxxx-dev-261102'));}
function checkPath(resource){assertTarget();assert(typeof resource==='string'&&resource.startsWith('/'),'An explicit API resource is required');const decoded=decodeURIComponent(resource);const project=decoded.match(/\/projects\/([^/:?]+)/),bucket=decoded.match(/\/b\/([^/?]+)/);if(project){assert(!PROTECTED.includes(project[1]),'Protected project resource refused');assert([TARGET,NUMBER].includes(project[1]),'API project is outside MYDOXXX');}if(bucket){assert(!PROTECTED.some(p=>bucket[1]===p+'.firebasestorage.app'||bucket[1]===p+'.appspot.com'),'Protected bucket resource refused');assert.equal(bucket[1],BUCKET,'API bucket is outside MYDOXXX');}assert(project||bucket,'API resource has no explicit destination project or bucket');}
async function session(){
 assertTarget();const auth=require(CLI+'/auth'),{requireAuth}=require(CLI+'/requireAuth'),{Client}=require(CLI+'/apiv2');
 const account=auth.getAllAccounts().find(a=>a.user.email===OWNER);assert(account,'Srinath Firebase CLI login is required');const options={project:TARGET,nonInteractive:true};auth.setActiveAccount(options,account);await requireAuth(options,true);
 // Explicitly clear access-token cache; this process never authenticates a second account.
 require(CLI+'/apiv2').setAccessToken();
 function api(host,version){const raw=new Client({urlPrefix:'https://'+host,...(version?{apiVersion:version}:{})});
  return {
   async get(resource,options={}){checkPath(resource);return raw.get(resource,{...options,skipLog:{body:true,resBody:true}});},
   async post(resource,body,options={}){checkPath(resource);return raw.post(resource,body,{...options,skipLog:{body:true,resBody:true}});},
   async patch(resource,body,options={}){checkPath(resource);return raw.patch(resource,body,{...options,skipLog:{body:true,resBody:true}});}
  };
 }
 const crm=api('cloudresourcemanager.googleapis.com','v1');const project=(await crm.get('/projects/'+TARGET)).body;assert.equal(project.projectId,TARGET);assert.equal(String(project.projectNumber),NUMBER);assert.equal(project.lifecycleState,'ACTIVE');
 const iam=(await crm.post('/projects/'+TARGET+':getIamPolicy',{})).body;assert((iam.bindings||[]).some(b=>b.role==='roles/owner'&&(b.members||[]).includes('user:'+OWNER)),'Expected owner is missing');
 return {api,async ensure(services){const enable=require(CLI+'/ensureApiEnabled');for(const service of services){assertTarget();await enable.ensure(TARGET,service,'mydoxxx recovery',true);}},anonymous(host,version){const raw=new Client({urlPrefix:'https://'+host,apiVersion:version,auth:false});return {get(resource){checkPath(resource);return raw.get(resource,{skipLog:{body:true,resBody:true}});}};}};
}
async function sourceDocuments(){const bytes=await fs.readFile(path.join(SOURCE,'firestore/documents.json'));const data=JSON.parse(bytes);assert.equal(data.project,'mydox-be432');assert.equal(data.complete,true);assert.equal(data.documents.length,562);return {data,digest:sha(bytes)};}
function transformedDocuments(data,storage){
 const map=new Map((storage?.files||[]).map(o=>[o.name,o]));if(storage){assert.equal(storage.target,TARGET);assert.equal(storage.bucket,BUCKET);assert.equal(storage.complete,true);}
 const changes={clearedFcmFields:[],removedFcmTokens:0,storageLinksRemapped:0,referenceValuesRemapped:0};
 function remapText(s){if(!storage)return s;if(s.startsWith('gs://mydox-be432.firebasestorage.app/'))return 'gs://'+BUCKET+'/'+s.slice('gs://mydox-be432.firebasestorage.app/'.length);let u;try{u=new URL(s);}catch{return s;}let name;
  if(u.hostname==='firebasestorage.googleapis.com'){const m=u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.*)$/);if(!m||decodeURIComponent(m[1])!=='mydox-be432.firebasestorage.app')return s;name=decodeURIComponent(m[2]);}
  else if(u.hostname==='storage.googleapis.com'&&u.pathname.startsWith('/mydox-be432.firebasestorage.app/'))name=decodeURIComponent(u.pathname.slice('/mydox-be432.firebasestorage.app/'.length));else return s;
  const f=map.get(name);assert(f,'Referenced Storage object missing from new-project receipt');return f.downloadToken?'https://firebasestorage.googleapis.com/v0/b/'+BUCKET+'/o/'+encodeURIComponent(name)+'?alt=media&token='+encodeURIComponent(f.downloadToken):'gs://'+BUCKET+'/'+name;
 }
 function fields(input,docPath,fieldPath=[]){return Object.fromEntries(Object.entries(input||{}).map(([key,val])=>{
  const fp=[...fieldPath,key];if(key==='fcmTokens'){assert(val.arrayValue,'Unexpected fcmTokens type; manual review required');const count=(val.arrayValue.values||[]).length;changes.clearedFcmFields.push({documentPath:docPath,fieldPath:fp.join('.'),removedEntries:count});changes.removedFcmTokens+=count;return [key,{arrayValue:{}}];}
  return [key,value(val,docPath,fp)];}));}
 function value(input,docPath,fp){const v=structuredClone(input);if(v.referenceValue?.startsWith(SRC_BASE+'/')){v.referenceValue=DST_BASE+v.referenceValue.slice(SRC_BASE.length);changes.referenceValuesRemapped++;}if(v.stringValue){const next=remapText(v.stringValue);if(next!==v.stringValue){changes.storageLinksRemapped++;v.stringValue=next;}}if(v.mapValue?.fields)v.mapValue.fields=fields(v.mapValue.fields,docPath,fp);if(v.arrayValue?.values)v.arrayValue.values=v.arrayValue.values.map((x,i)=>value(x,docPath,[...fp,String(i)]));return v;}
 const documents=data.documents.map(d=>{assert(d.name.startsWith(SRC_BASE+'/'));const relative=d.name.slice(SRC_BASE.length+1);return {name:DST_BASE+'/'+relative,fields:fields(d.fields,relative)};});assert.equal(new Set(documents.map(d=>d.name)).size,562);return {documents,changes};
}
async function batchGet(firestore,docs){const r=(await firestore.post('/'+DST_BASE+':batchGet',{documents:docs.map(d=>d.name)})).body;return new Map(r.filter(x=>x.found).map(x=>[x.found.name,x.found]));}
async function verifyDocuments(firestore,documents){let verified=0;for(let i=0;i<documents.length;i+=100){const chunk=documents.slice(i,i+100),actual=await batchGet(firestore,chunk);for(const d of chunk){assert(actual.has(d.name),'A restored document is missing');same(actual.get(d.name).fields||{},d.fields,'Restored document fields differ');verified++;}}return verified;}
async function lockedRules(api,kind){assert(['firestore','storage'].includes(kind));const content=await fs.readFile(path.join(RECOVERY,kind+'.rules'),'utf8');assert(content.includes('if false'));assert(!content.includes('if true'));const rules=api('firebaserules.googleapis.com','v1'),releaseName=`projects/${TARGET}/releases/`+(kind==='firestore'?'cloud.firestore':'firebase.storage/'+BUCKET);let release;
 try{release=(await rules.get('/'+releaseName)).body;}catch(e){if(e.status!==404)throw e;}
 if(release){const set=(await rules.get('/'+release.rulesetName)).body;same(set.source.files.map(f=>f.content).join('\n').trim(),content.trim(),'Existing rules differ from locked recovery rules; refusing overwrite');}
 else{const set=(await rules.post(`/projects/${TARGET}/rulesets`,{source:{files:[{name:kind+'.rules',content}]}})).body;release=(await rules.post(`/projects/${TARGET}/releases`,{name:releaseName,rulesetName:set.name})).body;}
 await fs.mkdir(OUT,{recursive:true});await fs.writeFile(path.join(OUT,kind+'.rules'),content);return release;
}
async function listObjects(storage){const objects=[];let pageToken;do{const body=(await storage.get('/storage/v1/b/'+BUCKET+'/o',{queryParams:{maxResults:1000,...(pageToken?{pageToken}:{})}})).body;objects.push(...body.items||[]);pageToken=body.nextPageToken;}while(pageToken);return objects;}
async function fail(name,error){await save(name,{target:TARGET,failedAt:new Date().toISOString(),error:error.message,protectedProjectsModified:false});console.error('MYDOXXX operation stopped: '+error.message);process.exitCode=1;}
module.exports={fs,path,crypto,assert,same,isDeepStrictEqual,ROOT,TARGET,NUMBER,OWNER,PROTECTED,SOURCE,OUT,RECOVERY,BUCKET,SRC_BASE,DST_BASE,CLI,sha,read,optional,save,assertTarget,checkPath,session,sourceDocuments,transformedDocuments,batchGet,verifyDocuments,lockedRules,listObjects,fail};
