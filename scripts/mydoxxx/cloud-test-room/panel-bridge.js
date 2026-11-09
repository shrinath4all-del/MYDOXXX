(function(){
  'use strict';
  const origin='https://mydoxxx-live-test.netlify.app';
  if(location.origin!==origin || location.pathname!=='/panel/') return;
  const roleKey=new URL(location.href).searchParams.get('role');
  const waiting=new Map();
  window.mydoxCloudTestLogin=function(requestedRole){
    return new Promise((resolve,reject)=>{
      if(requestedRole!==roleKey || window.parent===window){reject(Error('Open this role from the signed-in MyDox test room.'));return;}
      const requestId=crypto.randomUUID();
      const timer=setTimeout(()=>{waiting.delete(requestId);reject(Error('The test room did not respond. Sign in again and reload this role.'));},30000);
      waiting.set(requestId,{resolve,reject,timer});
      window.parent.postMessage({type:'mydox:role-request',requestId,roleKey},origin);
    });
  };
  window.addEventListener('message',event=>{
    if(event.origin!==origin || event.source!==window.parent || event.data?.type!=='mydox:role-response')return;
    const pending=waiting.get(event.data.requestId);if(!pending)return;
    waiting.delete(event.data.requestId);clearTimeout(pending.timer);
    if(event.data.error){pending.reject(Error('Sign in again from the test-room home page.'));return;}
    if(event.data.result?.roleKey!==roleKey){pending.reject(Error('Unexpected role response.'));return;}
    pending.resolve(JSON.stringify(event.data.result));
  });
})();
