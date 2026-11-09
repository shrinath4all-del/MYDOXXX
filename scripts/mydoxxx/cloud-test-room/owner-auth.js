import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-app.js';
import { getAuth, setPersistence, browserSessionPersistence, GoogleAuthProvider, signInWithPopup, onAuthStateChanged, signOut } from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-auth.js';
import { config } from './cloud-config.js';
if (location.origin !== config.origin) throw new Error('Open the approved MyDox testing address.');
export const auth = getAuth(initializeApp(config.firebase, 'mydox-lab-owner'));
// Sign-in needs session storage to survive the move to the room page. If a browser
// blocks it, report that clearly instead of failing the whole page.
export let storageBlocked = false;
try { await setPersistence(auth, browserSessionPersistence); } catch (_) { storageBlocked = true; }
export const ready = new Promise(resolve => { const stop = onAuthStateChanged(auth, user => { stop(); resolve(user); }); });
export const approved = user => Boolean(user && user.emailVerified && user.email?.toLowerCase() === config.owner && user.providerData.some(p => p.providerId === 'google.com'));
export async function login() {
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({login_hint: config.owner, prompt:'select_account'});
  return signInWithPopup(auth, provider);
}
export async function logout() { await signOut(auth); }
export async function requestRole(roleKey) {
  const user = auth.currentUser;
  if (!approved(user)) throw new Error('Sign in with the authorised MyDox account.');
  const ownerToken = await user.getIdToken();
  const response = await fetch(config.broker, {method:'POST', headers:{'Content-Type':'application/json',Authorization:'Bearer '+ownerToken}, body:JSON.stringify({roleKey}), cache:'no-store', credentials:'omit', signal:AbortSignal.timeout(25000)});
  if (!response.ok) throw new Error(response.status===403 || response.status===401 ? 'Your account is not authorised. Sign out and sign in again.' : 'The role service is temporarily unavailable. Retry in a moment.');
  const result = await response.json();
  if (result.projectId!==config.projectId || result.databaseId!==config.databaseId || result.roleKey!==roleKey || typeof result.customToken!=='string') throw new Error('The role service returned an unexpected response.');
  return {projectId:result.projectId,databaseId:result.databaseId,roleKey:result.roleKey,role:result.role,uid:result.uid,customToken:result.customToken};
}
