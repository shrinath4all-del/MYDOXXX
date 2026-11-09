// A client-side identity hint, not an authorization boundary. The broker still
// verifies the signed Google identity server-side before issuing any role token.
// The digest avoids publishing the operator's contact address in static assets.
export async function matchesOwner(user, expectedHash, subtle=globalThis.crypto?.subtle) {
  if (!user || user.emailVerified !== true || typeof user.email !== 'string' ||
      !Array.isArray(user.providerData) || !user.providerData.some(p => p?.providerId === 'google.com') ||
      typeof expectedHash !== 'string' || !/^[a-f0-9]{64}$/.test(expectedHash) || !subtle) return false;
  const email=user.email.trim().toLowerCase();
  if (!email) return false;
  try {
    const bytes=await subtle.digest('SHA-256',new TextEncoder().encode(email));
    const actual=Array.from(new Uint8Array(bytes),byte=>byte.toString(16).padStart(2,'0')).join('');
    return actual===expectedHash;
  } catch (_) { return false; }
}
