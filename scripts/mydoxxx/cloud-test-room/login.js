const button=document.getElementById('signin'), status=document.getElementById('status');
try {
  const {ready,approved,login,logout}=await import('./owner-auth.js');
  const user=await ready;
  if(approved(user)) location.replace('/room.html');
  else {
    if(user) await logout();
    button.disabled=false;button.textContent='Continue with Google';
    button.onclick=async()=>{button.disabled=true;status.textContent='';try{const result=await login();if(!approved(result.user)){await logout();throw Error('Please use shrinath4all@gmail.com for this private workspace.');}location.assign('/room.html');}catch(error){status.textContent=error.code==='auth/popup-closed-by-user'?'Sign-in was cancelled. You can try again.':error.code?'Google sign-in could not complete. Please try again.':error.message;button.disabled=false;}};
  }
}catch(_){status.textContent='Secure sign-in could not load. Check your internet connection and reload.';button.textContent='Reload this page';button.disabled=false;button.onclick=()=>location.reload();}
