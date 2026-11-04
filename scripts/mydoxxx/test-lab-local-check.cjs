// Offline checks only. No user creation, sign-in, Firebase writes or API calls.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const P=require('./test-lab-plan.cjs'),L=require('./test-lab.cjs'),C=require('./common.cjs');
assert.equal(P.ACCOUNTS.length,14);assert.equal(new Set(P.ACCOUNTS.map(a=>a.uid)).size,14);
for(const a of P.ACCOUNTS){L.checkAccount(a);assert(!a.uid.includes('_'));assert.throws(()=>L.checkAccount({...a,role:'admin'}));assert.throws(()=>L.checkAccount({...a,email:'somebody@example.com'}));}
P.checkLabPath('/'+P.BASE+'/documents:commit');P.checkLabPath('/'+P.BASE+'/collectionGroups/duties/indexes');
for(const project of [...C.PROTECTED,C.TARGET]){assert.throws(()=>P.checkLabPath(`/projects/${project}/databases/(default)/documents:commit`));}
assert.throws(()=>P.checkLabPath('/'+P.BASE+'-lookalike/documents:commit'));
const plan=P.fixturePlan('2026-11-02T09:00:00.000Z');assert.equal(new Set(plan.map(x=>x.path)).size,plan.length);
const paths=new Set(plan.map(x=>x.path));for(const a of P.ACCOUNTS){assert(paths.has('users/'+a.uid));assert(paths.has(a.collection+'/'+a.uid));}
for(const x of plan){assert(x.data.mydoxSynthetic===true);assert(!JSON.stringify(x.data).includes('https://'));assert(!JSON.stringify(x.data).includes('firebasestorage.app'));if(x.data.phone!==undefined)assert.equal(x.data.phone,'');if(x.data.path?.startsWith('assets/'))assert(fs.existsSync(path.join(C.ROOT,'experiments/MYDOXXX/app',x.data.path)));assert(P.fields(x.data));}
const text=P.rules();assert(text.includes("database == 'mydoxxx-testing'"));assert(text.includes('request.auth.token.mydoxTest == true'));assert(text.includes('request.auth.token.role == roles[request.auth.uid]'));for(const a of P.ACCOUNTS)assert(text.includes(a.uid));assert(!text.includes('if true'));
// Model the explicit UID/claim/database gate for the negative cases used by REST access checks.
const allow=(database,auth)=>database===P.DATABASE&&!!auth&&P.ACCOUNTS.some(a=>a.uid===auth.uid&&auth.mydoxTest===true&&auth.testDatabase===database&&auth.role===a.role);
for(const a of P.ACCOUNTS){const token={uid:a.uid,...P.claims(a)};assert(allow(P.DATABASE,token));assert(!allow('(default)',token));assert(!allow(P.DATABASE,{...token,uid:'copieduser'}));assert(!allow(P.DATABASE,{...token,mydoxTest:false}));assert(!allow(P.DATABASE,{...token,role:'admin'}));}assert(!allow(P.DATABASE,null));
console.log(JSON.stringify({localOnly:true,moduleLoadPassed:true,syntheticAccounts:P.ACCOUNTS.length,syntheticSeedDocuments:plan.length,exactTargetGuardPassed:true,claimAndUidNegativeCasesPassed:true,localAssetPathsPassed:true,credentialsGenerated:false,cloudCalls:0}));
