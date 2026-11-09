const C=require('../common.cjs');
const DOMAIN='mydoxxx-live-test.netlify.app';
async function main(){
 const s=await C.session(),admin=s.api('identitytoolkit.googleapis.com','admin/v2');
 const before=(await admin.get('/projects/'+C.TARGET+'/config')).body;
 C.assert.equal(before.subtype,'FIREBASE_AUTH','Keep basic Firebase Authentication');
 if(process.argv.includes('--apply')){
   const {provisionFirebaseApp}=require(C.CLI+'/management/provisioning/provision');
   await provisionFirebaseApp({project:{parent:{type:'existing_project',projectId:C.TARGET}},app:{platform:'WEB',appId:'1:724915428929:web:ce9c0a4ab47a83e70d70c0'},features:{firebaseAuthInput:{googleSigninProviderMode:'PROVIDER_ENABLED',googleSigninProviderConfig:{publicDisplayName:'MyDox Private Test Room',customerSupportEmail:C.OWNER,oauthRedirectUris:['https://'+C.TARGET+'.firebaseapp.com/__/auth/handler']}}}});
   const afterProvision=(await admin.get('/projects/'+C.TARGET+'/config')).body;
   C.assert.equal(afterProvision.subtype,'FIREBASE_AUTH','Unexpected Auth subtype; stop');
   const domains=[...new Set([...(afterProvision.authorizedDomains||[]),DOMAIN])];
   if(!afterProvision.authorizedDomains?.includes(DOMAIN))await admin.patch('/projects/'+C.TARGET+'/config',{authorizedDomains:domains},{queryParams:{updateMask:'authorizedDomains'}});
 }
 const after=(await admin.get('/projects/'+C.TARGET+'/config')).body;
 C.assert.equal(after.subtype,'FIREBASE_AUTH');
 C.same(after.signIn.email,before.signIn.email,'Email provider unexpectedly changed');
 C.same(after.signIn.phoneNumber,before.signIn.phoneNumber,'Phone provider unexpectedly changed');
 let google;try{google=(await admin.get('/projects/'+C.TARGET+'/defaultSupportedIdpConfigs/google.com')).body;}catch(e){if(e.status!==404)throw e;google={enabled:false};}
 const report={target:C.TARGET,googleEnabled:google.enabled===true,hasOAuthClient:Boolean(google.clientId),domainAuthorised:after.authorizedDomains.includes(DOMAIN),basicAuth:true,otherSignInProvidersPreserved:true,checkedAt:new Date().toISOString()};
 if(process.argv.includes('--apply')){C.assert(report.googleEnabled&&report.hasOAuthClient&&report.domainAuthorised);await C.save('cloud-google-signin-setup.json',report);}
 console.log(JSON.stringify(report));
}
main().catch(e=>{console.error('Cloud sign-in setup stopped: '+e.message);process.exitCode=1;});
