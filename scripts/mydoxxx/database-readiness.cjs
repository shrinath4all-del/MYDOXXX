// Firestore control-plane creation can complete before document reads are ready.
// Retry only read-only collection discovery, never a write or authorization error.
async function waitForDatabaseReads(readCollections,options={}){
 const attempts=options.attempts??15;
 const pause=options.pause??(ms=>new Promise(resolve=>setTimeout(resolve,ms)));
 let last;
 for(let attempt=0;attempt<attempts;attempt++){
  try{return await readCollections();}catch(error){
   const status=Number(error.status);
   const notReady=status===404&&/database.*does not exist|database.*not found/i.test(error.message||'');
   if(!notReady&&status!==429&&status!==503)throw error;
   last=error;
   if(attempt===attempts-1)break;
   if(options.onRetry)options.onRetry({attempt:attempt+1,status});
   await pause(Math.min(1000*2**attempt,5000));
  }
 }
 const error=new Error('MYDOXXX database metadata exists, but document reads are not ready after bounded retries. No records were written; retry the restore after propagation.');
 error.cause=last;throw error;
}
module.exports={waitForDatabaseReads};
