// Pure synthetic fixtures. Importing this module never contacts Firebase.
const C=require('./common.cjs');
const DATABASE='mydoxxx-testing';
const BASE=`projects/${C.TARGET}/databases/${DATABASE}`;
const ACCOUNTS=Object.freeze([
 ['patient','patients','Test Patient'],['doctor','doctors','Test Doctor'],
 ['nurse','nurses','Test Nurse'],['hospital','hospitals','Test Hospital'],
 ['ambulance','ambulances','Test Ambulance'],['care_physician','care_physicians','Test Care Physician'],
 ['technician','technicians','Test Technician'],['therapist','therapists','Test Therapist'],
 ['care_physician_2','care_physicians','Test Care Physician Two'],['care_physician_3','care_physicians','Test Care Physician Three'],
 ['agency_care','agencies','Test Care Agency'],['agency_nurse','agencies','Test Nursing Agency'],
 ['agency_technician','agencies','Test Technician Agency'],['agency_physio','agencies','Test Physio Agency']
].map(([key,collection,name])=>Object.freeze({key,roleKey:key,role:key.startsWith('agency_')?'agency':key.startsWith('care_physician')?'care_physician':key,collection,name,uid:'mdxtest'+key.replaceAll('_',''),email:key.replaceAll('_','')+'@mydoxxx-test.invalid'})));
const byKey=Object.fromEntries(ACCOUNTS.map(a=>[a.key,a]));
function claims(a){return {mydoxTest:true,testDatabase:DATABASE,role:a.role};}
function checkLabPath(resource){C.checkPath(resource);C.assert(resource.startsWith('/'+BASE+'/')||resource==='/'+BASE||resource.startsWith('/'+BASE+':'),'Only the synthetic named database is writable');}
function rules(){const roles=Object.fromEntries(ACCOUNTS.map(a=>[a.uid,a.role]));return `rules_version = '2';
// PRIVATE SYNTHETIC FUNCTIONAL TEST LAB. Not production role authorization.
// The restored (default) database is deliberately excluded, even if misdeployed.
service cloud.firestore {
  match /databases/{database}/documents {
    function isLabUser() {
      let roles = ${JSON.stringify(roles)};
      return database == '${DATABASE}'
        && request.auth != null
        && request.auth.uid in roles
        && request.auth.token.mydoxTest == true
        && request.auth.token.testDatabase == database
        && request.auth.token.role == roles[request.auth.uid];
    }
    match /{document=**} {
      allow read, write: if isLabUser();
    }
  }
}
`;}
function value(v){if(v===null)return {nullValue:null};if(typeof v==='string')return {stringValue:v};if(typeof v==='boolean')return {booleanValue:v};if(typeof v==='number')return Number.isInteger(v)?{integerValue:String(v)}:{doubleValue:v};if(Array.isArray(v))return {arrayValue:{values:v.map(value)}};return {mapValue:{fields:fields(v)}};}
function fields(v){return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,value(x)]));}
function fixturePlan(at){
 const started=new Date(at);C.assert(!Number.isNaN(+started));const iso=started.toISOString();const records=[];
 const add=(path,data)=>records.push({path,data:{...data,mydoxSynthetic:true}});
 const locations=['Pune','PCMC','Wakad','Hinjewadi','Pimpri','Chinchwad'];
 for(const a of ACCOUNTS){
  const profile={uid:a.uid,role:a.role,name:a.name,email:a.email,phone:'',mobileNumber:'',isVerified:true,isOnline:true,available:true,blocked:false,isBlocked:false,active:true,latitude:18.5994,longitude:73.7620,city:'Wakad',area:'Wakad',preferredLocations:locations,areas:locations,rating:4.8,createdAt:iso,updatedAt:iso,profilePicUrl:'',fcmTokens:[]};
  if(a.role==='patient')Object.assign(profile,{age:'45',bloodGroup:'O+',weight:'70',allergy:'Synthetic test record only',homeAddress:'Test home, Wakad',emergencyContact:'',preferredDoctorUids:[byKey.doctor.uid],preferredDoctorNames:[byKey.doctor.name]});
  if(a.role==='doctor')Object.assign(profile,{category:'General Physician',qualification:'MBBS',experience:'8',hospital:byKey.hospital.name,hospitalUid:byKey.hospital.uid,organisation:byKey.hospital.name});
  if(a.role==='hospital')Object.assign(profile,{hospital:a.name,locationLocked:true,facilityType:'Hospital',type:'Hospital',address:'Synthetic testing facility, Wakad',latitude:18.6000,longitude:73.7630,hospitalPreferredDoctors:{'General Physician':[byKey.doctor.uid]},hospitalPreferredDoctorNames:{'General Physician':[byKey.doctor.name]},totalBeds:20,availableBeds:8,icuBeds:4,availableIcuBeds:2});
  if(a.role==='ambulance')Object.assign(profile,{vehicleNumber:'TEST-AMB-01',vehicleType:'BLS',ambulanceType:'BLS',driverName:a.name,isBusy:false,latitude:18.6002,longitude:73.7615});
  if(['care_physician','nurse','technician','therapist'].includes(a.role)){
   const agencyKey={care_physician:'agency_care',nurse:'agency_nurse',technician:'agency_technician',therapist:'agency_physio'}[a.role];
   Object.assign(profile,{qualification:{care_physician:'MBBS',nurse:'GNM',technician:'DMLT',therapist:'BPT'}[a.role],experience:'5',experienceYears:5,organisation:byKey[agencyKey].name,agencyId:byKey[agencyKey].uid,agencyName:byKey[agencyKey].name,workMode:'agency',regNo:'SYNTHETIC-TEST-ONLY',procedures:['general_visit','dressing'],dutyTypes:['home','ward','icu','casualty','specialty'],ageGroups:['adult','paediatric','geriatric'],specialties:[],noShows:0,preferredHospitals:[byKey.hospital.uid]});
   if(a.role==='technician')Object.assign(profile,{category:'Lab Technician',tests:['CBC','ECG'],labTests:['CBC','ECG'],skills:['CBC','ECG'],services:['CBC','ECG']});
   if(a.role==='therapist')Object.assign(profile,{category:'Physiotherapy',therapies:['Physiotherapy'],skills:['Physiotherapy']});
  }
  if(a.role==='agency')Object.assign(profile,{agencyType:{agency_care:'care_physician',agency_nurse:'nurse',agency_technician:'technician',agency_physio:'physio'}[a.key],splitDoctorPct:80,splitAgencyPct:15,splitAppPct:5,acceptWindowMin:1,serviceAreas:locations,servingAreas:locations});
  add(`${a.collection}/${a.uid}`,profile);add(`users/${a.uid}`,profile);
 }
 for(const a of ACCOUNTS.filter(a=>['care_physician','nurse','technician'].includes(a.role))){const agency=byKey[{care_physician:'agency_care',nurse:'agency_nurse',technician:'agency_technician'}[a.role]];add(`agency_doctors/${agency.uid}_${a.uid}`,{agencyId:agency.uid,userUid:a.uid,name:a.name,phone:'',qualification:a.role==='care_physician'?'MBBS':a.role==='nurse'?'GNM':'DMLT',regNo:'SYNTHETIC-TEST-ONLY',placementType:'pool',active:true,joinedBy:'test-lab',createdAt:iso});}
 for(const key of ['agency_care','agency_nurse','agency_technician'])add(`agency_hospitals/${byKey[key].uid}_${byKey.hospital.uid}`,{agencyId:byKey[key].uid,hospitalUid:byKey.hospital.uid,name:byKey.hospital.name,area:'Wakad',contactName:'Test Coordinator',contactPhone:'',active:true});
 add('app_settings/pricing',{urgentSurchargePct:20,doctorHomeVisitExtra:800,nurseDailyRate:800,sosEmergencyFee:500,emergencyLocumHikePct:20});
 add('category_doctors/general_physician',{name:'General Physician',price:500,isActive:true,order:1});
 add('lab_tests/cbc',{name:'CBC',price:350,isActive:true,order:1});add('lab_tests/ecg',{name:'ECG',price:450,isActive:true,order:2});
 add('therapies/physiotherapy',{name:'Physiotherapy',price:600,isActive:true,order:1});
 for(const collection of ['care_physician_services','nurse_services','technician_services']){add(`${collection}/general_visit`,{name:collection==='care_physician_services'?'General home visit':'Home-care support',price:800,needsVerified:true,isActive:true,active:true,order:1});add(`${collection}/dressing`,{name:'Dressing support',price:500,needsVerified:true,isActive:true,active:true,order:2});}
 for(const collection of ['care_duty_rates','nurse_duty_rates','technician_duty_rates'])for(const [unit,label,rate] of [['ward','Ward duty',1500],['icu','ICU duty',2000],['casualty','Casualty / ER',1800],['specialty','Specialty duty',2000]])add(`${collection}/${unit}`,{label,hospitalRate:rate,monthlySalary:rate*24,platformMarginPct:15,saiSharePct:75,mydoxSharePct:25,active:true});
 for(const [collection,names] of [['location_master',locations],['area_master',locations],['language_master',['English','Hindi','Marathi']],['nurse_qualifications',['GNM','BSc Nursing']],['technician_qualifications',['DMLT','BSc MLT']],['therapist_qualifications',['BPT','MPT']]])names.forEach((name,i)=>add(`${collection}/test${i+1}`,{name,order:i+1,isActive:true}));
 for(const [key,path] of [['service:doctor','assets/doctors.png'],['service:nurse','assets/nurses.png'],['service:technician','assets/technician.png'],['specialty:General Physician','assets/general.png']])add('images_master/'+key,{key,path,active:true});
 const slots=[];for(let minutes=8*60;minutes<=21*60;minutes+=30){const h=Math.floor(minutes/60),m=minutes%60;slots.push(`${String(h%12||12).padStart(2,'0')}:${String(m).padStart(2,'0')} ${h>=12?'PM':'AM'}`);}
 // Store date-specific availability for two weeks; no existing appointments are overwritten.
 const day=new Date(started.getTime()+330*60000);day.setUTCHours(0,0,0,0);
 for(let d=0;d<14;d++){const dateKey=new Date(+day+d*86400000).toISOString().slice(0,10);for(const key of ['doctor','nurse','technician','therapist'])add(`doctor_schedules/${byKey[key].uid}/dates/${dateKey}`,{dateKey,isAvailable:true,timeSlots:slots,updatedAt:iso});}
 for(const a of ACCOUNTS.filter(a=>['care_physician','nurse','technician'].includes(a.role)))add(`${{care_physician:'care_physician_schedules',nurse:'nurse_schedules',technician:'technician_schedules'}[a.role]}/${a.uid}`,{slots:{}});
 const completedAt=new Date(+started-5*60000).toISOString();
 for(const key of ['doctor','nurse','technician','therapist']){const provider=byKey[key];add(`appointments/mdxtestcompleted${key}`,{id:'mdxtestcompleted'+key,appointmentId:'mdxtestcompleted'+key,patientUid:byKey.patient.uid,patientName:byKey.patient.name,patientPhone:'',doctorUid:provider.uid,doctorName:provider.name,doctorCategory:key==='doctor'?'General Physician':key,hospital:byKey.hospital.name,roleTarget:key,isNurseRequest:key==='nurse',isTechnicianRequest:key==='technician',isTherapistRequest:key==='therapist',status:'Completed',type:'Synthetic completed consultation',date:day.toISOString().slice(0,10),time:'08:00 AM',locationName:'Wakad',locationType:'Clinic',consultationType:'Clinic/Visit',price:0,basePrice:0,paymentStatus:'cash_collected',hasBeenRated:false,createdAt:completedAt,completedAt,isBroadcast:false,declinedBy:[]});}
 add('lab_metadata/config',{projectId:C.TARGET,databaseId:DATABASE,createdAt:iso,syntheticOnly:true,purpose:'Private multi-role functional testing; not production authorization',externalPayments:false,externalMessages:false,roleKeys:ACCOUNTS.map(a=>a.key)});
 C.assert.equal(new Set(records.map(r=>r.path)).size,records.length);return records;
}
module.exports={DATABASE,BASE,ACCOUNTS,byKey,claims,checkLabPath,rules,value,fields,fixturePlan};
