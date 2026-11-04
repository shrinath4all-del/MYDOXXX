// Firebase Rules test API evaluates these contexts without reading/writing app records.
const C=require('./common.cjs'),P=require('./test-lab-plan.cjs');
function cases(){const tests=[];function add(label,expectation,database,method,auth){tests.push({label,expectation,request:{path:`/databases/${database}/documents/lab_metadata/config`,method,auth,resource:{data:{syntheticOnly:true}}},resource:{data:{syntheticOnly:true}},pathEncoding:'PLAIN'});}
 for(const a of P.ACCOUNTS)add('allowed-'+a.key,'ALLOW',P.DATABASE,'get',{uid:a.uid,token:P.claims(a)});
 const a=P.ACCOUNTS[0],auth={uid:a.uid,token:P.claims(a)};
 for(const method of ['get','list','create','update','delete']){add('allowed-'+method,'ALLOW',P.DATABASE,method,auth);add('default-denied-'+method,'DENY','(default)',method,auth);}
 add('anonymous','DENY',P.DATABASE,'get',null);
 add('ordinary-user','DENY',P.DATABASE,'get',{uid:'ordinaryuser',token:{}});
 add('copied-user-even-with-test-claims','DENY',P.DATABASE,'get',{uid:'copieduser',token:P.claims(a)});
 add('no-claims','DENY',P.DATABASE,'get',{uid:a.uid,token:{}});
 add('wrong-role','DENY',P.DATABASE,'get',{uid:a.uid,token:{...P.claims(a),role:'admin'}});
 add('wrong-database-claim','DENY',P.DATABASE,'get',{uid:a.uid,token:{...P.claims(a),testDatabase:'(default)'}});
 add('wrong-marker-type','DENY',P.DATABASE,'get',{uid:a.uid,token:{...P.claims(a),mydoxTest:'true'}});
 add('lookalike-database','DENY',P.DATABASE+'-other','get',auth);return tests;
}
async function main(){const connected=await C.session(),rules=connected.api('firebaserules.googleapis.com','v1');const plan=cases();const result=(await rules.post(`/projects/${C.TARGET}:test`,{source:{files:[{name:'firestore-testing.rules',content:P.rules()}]},testSuite:{testCases:plan.map(({label,...x})=>x)}})).body;const report={target:C.TARGET,databaseId:P.DATABASE,cloudRecordsWritten:0,ruleReleasesChanged:0,issues:result.issues||[],tests:plan.map((p,i)=>({name:p.label,expectation:p.expectation,state:result.testResults?.[i]?.state||'MISSING',debugMessages:result.testResults?.[i]?.debugMessages||[]}))};await C.save('test-lab-rule-test.json',report);C.assert.equal(report.tests.length,54);C.assert(report.tests.every(t=>t.state==='SUCCESS'),'A synthetic database isolation rule test failed; inspect private report');C.assert(!report.issues.some(i=>i.severity==='ERROR'));console.log(JSON.stringify({target:C.TARGET,databaseId:P.DATABASE,ruleCasesPassed:report.tests.length,cloudRecordsWritten:0,ruleReleasesChanged:0}));}
if(require.main===module)main().catch(e=>{console.error('Synthetic rule check stopped: '+(e.code==='ERR_ASSERTION'?e.message:(e.status||e.code||'API error')));process.exitCode=1;});
module.exports={cases};
