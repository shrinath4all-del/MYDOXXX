// Offline safety checks. No Firebase requests, no credentials, no writes.
const A=require('node:assert/strict'),O=require('./test-lab-otp.cjs'),P=require('./test-lab-plan.cjs');
const fields=P.fields({patientUid:'mdxtestpatient',doctorUid:'mdxtestdoctor',otp:'1234',doctorOtp:1234,otpAttempts:2,otpLockedUntil:'unchanged',status:'Confirmed',price:100});
const known=new Set(['appointments/example','patients/mdxtestpatient']);
const result=O.patchFor('appointments/example',fields,known);A.deepEqual(result.patch,{otp:{stringValue:'7777'},doctorOtp:{integerValue:'7777'}});A.deepEqual(fields.otp,{stringValue:'1234'});A.equal(result.patch.otpAttempts,undefined);A.equal(result.patch.otpLockedUntil,undefined);A.equal(result.patch.status,undefined);A.equal(result.patch.price,undefined);
A.equal(O.patchFor('appointments/nootp',P.fields({patientUid:'mdxtestpatient'}),known),null);
A.deepEqual(O.patchFor('appointments/example',{...fields,otp:{stringValue:'7777'},doctorOtp:{integerValue:'7777'}},known).patch,{});
const unissued=O.patchFor('appointments/example',{patientUid:fields.patientUid,otp:{stringValue:''},doctorOtp:{nullValue:null}},known);A.deepEqual(unissued.patch,{});A.equal(unissued.ignoredUnissuedFields.length,2);
for(const value of [{stringValue:'123456'},{stringValue:'abc'},{booleanValue:true},{mapValue:{fields:{}}}])A.throws(()=>O.patchFor('appointments/example',{...fields,otp:value},known));
A.throws(()=>O.patchFor('users/mdxtestpatient',fields,known));A.throws(()=>O.patchFor('appointments/a/nested/b',fields,known));
A.throws(()=>O.patchFor('appointments/example',{...fields,patientUid:{stringValue:'realperson'}},known));A.throws(()=>O.patchFor('appointments/example',{...fields,doctorUid:{stringValue:'mdxtestunknown'}},known));
A.throws(()=>O.patchFor('appointments/example',{...fields,phoneOtp:{stringValue:'1234'}},known));
A.throws(()=>O.patchFor('appointments/example',{...fields,nested:{mapValue:{fields:{otp:{stringValue:'1234'}}}}},known));
A.throws(()=>O.patchFor('appointments/example',{...fields,patientRef:{referenceValue:'projects/mydox-be432/databases/(default)/documents/patients/a'}},known));
A.throws(()=>O.patchFor('appointments/example',{...fields,patientRef:{referenceValue:P.BASE+'/documents/patients/unknown'}},known));
A(O.patchFor('appointments/example',{...fields,patientRef:{referenceValue:P.BASE+'/documents/patients/mdxtestpatient'}},known));
for(const [collection,uid] of [['shifts','mdxtestcarephysician'],['nurse_shifts','mdxtestnurse'],['technician_shifts','mdxtesttechnician']]){
 const s=P.fields({posterId:'mdxtesthospital',claimedBy:uid,arrivalOtp:'4321',arrivalOtpAt:'unchanged',status:'claimed',arrivalLat:18.5994});const patch=O.patchFor(collection+'/shift',s,known).patch;A.deepEqual(patch,{arrivalOtp:{stringValue:'7777'}});A.throws(()=>O.patchFor(collection+'/shift',{...s,claimedBy:{stringValue:'mdxtestpatient'}},known));
}
console.log(JSON.stringify({localOnly:true,existingCodeFieldsOnly:true,scalarTypesPreserved:true,unissuedCodesUntouched:true,unknownActorsCollectionsFieldsAndReferencesRejected:true,attemptsLocksExpiryStatusPriceGpsUntouched:true,cloudCalls:0}));
