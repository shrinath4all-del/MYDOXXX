const button=document.getElementById('signin'), status=document.getElementById('status');
try {
  const {friendlyError,signInMessage,watchSlow,SLOW_POPUP_MESSAGE,STORAGE_BLOCKED_MESSAGE}=await import('./login-support.js');
  const {ready,approved,login,logout,storageBlocked}=await import('./owner-auth.js');
  const user=await ready;
  if(approved(user)) location.replace('/room.html');
  else if(storageBlocked){status.textContent=STORAGE_BLOCKED_MESSAGE;button.textContent='Reload this page';button.disabled=false;button.onclick=()=>location.reload();}
  else {
    if(user) await logout();
    button.disabled=false;button.textContent='Continue with Google';
    button.onclick=async()=>{
      button.disabled=true;status.textContent='';
      // A popup that never opens leaves no error to react to: offer guidance and a retry.
      const stopWatching=watchSlow(45000,()=>{status.textContent=SLOW_POPUP_MESSAGE;button.disabled=false;});
      try{const result=await login();if(!approved(result.user)){await logout();throw friendlyError('Please use shrinath4all@gmail.com for this private workspace.');}location.assign('/room.html');}
      catch(error){status.textContent=signInMessage(error);button.disabled=false;}
      finally{stopWatching();}
    };
  }
}catch(_){status.textContent='Secure sign-in could not load. Check your internet connection and reload.';button.textContent='Reload this page';button.disabled=false;button.onclick=()=>location.reload();}
