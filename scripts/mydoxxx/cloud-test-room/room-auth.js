import { config } from './cloud-config.js';
import { auth,ready,approved,requestRole,logout } from './owner-auth.js';
const user=await ready;
if(!await approved(user)) location.replace('/private.html');
else {
  const banner=document.createElement('div');banner.className='cloud-owner-bar';
  const info=document.createElement('span');info.textContent='PRIVATE CLOUD · '+user.email+' · Test sessions last up to 8 hours';
  const out=document.createElement('button');out.className='button';out.textContent='Sign out';
  banner.append(info,out);document.body.prepend(banner);
  out.onclick=async()=>{for(const frame of document.querySelectorAll('#room iframe'))frame.remove();await logout();location.replace('/private.html');};
  const pending=new WeakSet();
  window.addEventListener('message',async event=>{
    if(event.origin!==config.origin || event.data?.type!=='mydox:role-request')return;
    const {requestId,roleKey}=event.data;
    if(typeof requestId!=='string'||requestId.length>80||typeof roleKey!=='string')return;
    const frame=Array.from(document.querySelectorAll('#room iframe')).find(f=>f.contentWindow===event.source);
    if(!frame||pending.has(frame))return;
    const url=new URL(frame.src);
    if(url.origin!==config.origin||url.pathname!=='/panel/'||url.searchParams.get('role')!==roleKey)return;
    pending.add(frame);
    const ownerUid=auth.currentUser?.uid;
    try{const result=await requestRole(roleKey);const currentUser=auth.currentUser;const ownerApproved=await approved(currentUser);const current=new URL(frame.src);if(ownerApproved&&auth.currentUser?.uid===ownerUid&&frame.isConnected&&frame.contentWindow===event.source&&current.origin===config.origin&&current.pathname==='/panel/'&&current.searchParams.get('role')===roleKey)event.source.postMessage({type:'mydox:role-response',requestId,result},config.origin);}
    catch(_){if(frame.isConnected)event.source.postMessage({type:'mydox:role-response',requestId,error:true},config.origin);}
    finally{pending.delete(frame);}
  });
  window.MyDoxCloudRoom=Object.freeze({origin:config.origin});
  for(const src of ['/test-console-state.js','/test-console.js'])await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.onload=resolve;s.onerror=reject;document.body.append(s);});
  document.documentElement.classList.remove('checking-owner');
}

