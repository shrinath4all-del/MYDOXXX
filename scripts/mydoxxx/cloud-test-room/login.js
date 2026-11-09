const button=document.getElementById('signin'), status=document.getElementById('status');
try {
  const {friendlyError,signInMessage,watchSlow,SLOW_POPUP_MESSAGE,STORAGE_BLOCKED_MESSAGE}=await import('./login-support.js');
  const {ready,approved,login,logout,storageBlocked}=await import('./owner-auth.js');
  const user=await ready;
  if(await approved(user)) location.replace('/room.html');
  else if(storageBlocked){status.textContent=STORAGE_BLOCKED_MESSAGE;button.textContent='Reload this page';button.disabled=false;button.onclick=()=>location.reload();}
  else {
    if(user) await logout();
    button.disabled=false;button.textContent='Continue with Google';
    let latestAttempt=0;
    button.onclick=async()=>{
      const attempt=++latestAttempt, isCurrent=()=>attempt===latestAttempt;
      button.disabled=true;status.textContent='';
      // This observes a pending result, not whether the browser opened a popup.
      const stopWatching=watchSlow(45000,()=>{if(isCurrent()){status.textContent=SLOW_POPUP_MESSAGE;button.disabled=false;}});
      try{const result=await login();if(!isCurrent())return;const allowed=await approved(result.user);if(!isCurrent())return;if(!allowed){await logout();if(!isCurrent())return;throw friendlyError('Please use the authorised Google account for this private workspace.');}if(isCurrent())location.assign('/room.html');}
      catch(error){if(isCurrent()){status.textContent=signInMessage(error);button.disabled=false;}}
      finally{stopWatching();}
    };
  }
}catch(_){status.textContent='Secure sign-in could not load. Check your internet connection and reload.';button.textContent='Reload this page';button.disabled=false;button.onclick=()=>location.reload();}

