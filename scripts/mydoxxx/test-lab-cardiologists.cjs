// User-requested synthetic profile migration. No Auth, rules, history or default-DB writes.
const C = require('./common.cjs');
const P = require('./test-lab-plan.cjs');
const L = require('./test-lab.cjs');
const RECEIPT = 'test-lab-cardiologists-review.json';
const DONE = 'test-lab-cardiologists-verification.json';
const names = Object.fromEntries([1,2,3].map(n => ['mdxtestdoctor' + (n === 1 ? '' : n), 'Cardiologist ' + n]));
const paths = ['category_doctors/general_physician'];
for (const n of [1,2,3]) for (const [family,collection] of [['doctor','doctors'],['patient','patients'],['hospital','hospitals']]) {
  const uid = 'mdxtest' + family + (n === 1 ? '' : n);
  paths.push(collection + '/' + uid, 'users/' + uid);
}
function decode(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k,x]) => [k,decode(x)]));
  throw Error('Unexpected field type');
}
function changes(path, fields) {
  C.assert.equal(fields.mydoxSynthetic?.booleanValue, true, 'Only synthetic profiles are eligible');
  if (path === paths[0]) {
    C.assert(['General Physician','Cardiologist'].includes(fields.name?.stringValue));
    return {name:'Cardiologist'};
  }
  const uid = path.split('/')[1];
  if (names[uid]) {
    C.assert(['General Physician','Cardiologist'].includes(fields.category?.stringValue));
    return {name:names[uid], category:'Cardiologist'};
  }
  if (uid.startsWith('mdxtestpatient')) {
    const preferred = decode(fields.preferredDoctorUids);
    C.assert(preferred.every(x => Object.hasOwn(names,x)), 'Unexpected preferred doctor');
    return {preferredDoctorNames:preferred.map(x => names[x])};
  }
  C.assert(uid.startsWith('mdxtesthospital'));
  const doctors = decode(fields.hospitalPreferredDoctors);
  const labels = decode(fields.hospitalPreferredDoctorNames);
  const selected = [...new Set([...(doctors['General Physician'] || []), ...(doctors.Cardiologist || [])])];
  C.assert(selected.length && selected.every(x => Object.hasOwn(names,x)), 'Unexpected hospital preference');
  delete doctors['General Physician']; delete labels['General Physician'];
  doctors.Cardiologist = selected; labels.Cardiologist = selected.map(x => names[x]);
  return {hospitalPreferredDoctors:doctors, hospitalPreferredDoctorNames:labels};
}
async function context() {
  const ctx = await L.adminContext();
  const db = (await ctx.firestore.get('/' + P.BASE)).body;
  C.assert.equal(db.name,P.BASE); C.assert.equal(db.databaseEdition,'STANDARD');
  return ctx;
}
async function readPlan(ctx) {
  const actual = await L.batchGet(ctx,paths.map(path => ({path})));
  C.assert.equal(actual.size,paths.length);
  return paths.map(path => {
    const d = actual.get(path);
    return {path, before:d.fields, updateTime:d.updateTime, patch:changes(path,d.fields)};
  });
}
async function main() {
  const action = process.argv[2]; C.assert(['review','apply','verify'].includes(action));
  const ctx = await context();
  if (action === 'review') {
    const plan = await readPlan(ctx);
    await C.save(RECEIPT,{target:C.TARGET,databaseId:P.DATABASE,at:new Date().toISOString(),plan});
    console.log(JSON.stringify({target:C.TARGET,databaseId:P.DATABASE,edition:'STANDARD',documents:plan.length,names:Object.values(names),cloudWrites:0,historyUnchanged:true})); return;
  }
  const review = await C.read(C.path.join(C.OUT,RECEIPT));
  C.assert.equal(review.target,C.TARGET); C.assert.equal(review.databaseId,P.DATABASE);
  C.same(review.plan.map(x => x.path),paths);
  for (const item of review.plan) C.same(item.patch,changes(item.path,item.before));
  if (action === 'apply') {
    C.assert(Date.now()-Date.parse(review.at)<3600000,'Review the current profiles again');
    const current = await readPlan(ctx); C.same(current,review.plan,'Profile changed since review; refresh review without overwriting');
    const writes = review.plan.map(r => ({update:{name:P.BASE+'/documents/'+r.path,fields:P.fields(r.patch)},updateMask:{fieldPaths:Object.keys(r.patch)},currentDocument:{updateTime:r.updateTime}}));
    await ctx.post('/'+P.BASE+'/documents:commit',{writes});
  }
  const actual = await L.batchGet(ctx,paths.map(path => ({path})));
  for (const item of review.plan) C.same(actual.get(item.path).fields,{...item.before,...P.fields(item.patch)},'Unexpected profile result');
  const result={target:C.TARGET,databaseId:P.DATABASE,at:new Date().toISOString(),names:Object.values(names),specialty:'Cardiologist',verifiedDocuments:paths.length,existingUidsPreserved:true,authAndCredentialsChanged:false,appointmentHistoryChanged:false,defaultDatabaseChanged:false};
  await C.save(DONE,result); console.log(JSON.stringify(result));
}
if (require.main === module) main().catch(e => {console.error(e.code === 'ERR_ASSERTION' ? e.message : 'Cardiologist profile migration failed; no credentials printed.');process.exitCode=1;});
module.exports={changes,paths,names};
