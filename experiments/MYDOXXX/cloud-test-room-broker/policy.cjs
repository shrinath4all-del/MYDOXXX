'use strict';

const PROJECT = 'mydoxxx-dev-261102';
const DATABASE = 'mydoxxx-testing';
const OWNER_EMAIL = 'shrinath4all@gmail.com';
const SERVICE_ACCOUNT = `mydoxxx-lab-broker@${PROJECT}.iam.gserviceaccount.com`;
const MAX_BODY_BYTES = 512;
const MAX_TOKEN_BYTES = 8192;
const LAB_SESSION_MS = 8 * 60 * 60 * 1000;
const FAMILIES = Object.freeze([
  'patient', 'doctor', 'nurse', 'hospital', 'ambulance', 'care_physician',
  'technician', 'therapist', 'agency_care', 'agency_nurse',
  'agency_technician', 'agency_physio',
]);
const ROLES = Object.freeze(Object.fromEntries(FAMILIES.flatMap(family => [1, 2, 3].map(person => {
  const key = family + (person === 1 ? '' : `_${person}`);
  return [key, Object.freeze({roleKey: key, role: family.startsWith('agency_') ? 'agency' : family,
    uid: `mdxtest${key.replaceAll('_', '')}`})];
}))));

class PolicyError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
function deny(status, code) { throw new PolicyError(status, code); }

function configFromEnv(env) {
  const projects = [env.GCLOUD_PROJECT, env.GOOGLE_CLOUD_PROJECT].filter(Boolean);
  if (!projects.length || projects.some(p => p !== PROJECT) || env.FIREBASE_AUTH_EMULATOR_HOST) {
    deny(503, 'configuration_unavailable');
  }
  if (env.FIREBASE_CONFIG) {
    let config;
    try { config = JSON.parse(env.FIREBASE_CONFIG); } catch { deny(503, 'configuration_unavailable'); }
    if (config.projectId !== PROJECT) deny(503, 'configuration_unavailable');
  }
  const origin = env.MYDOX_CLOUD_ORIGIN;
  let url;
  try { url = new URL(origin); } catch { deny(503, 'configuration_unavailable'); }
  if (url.protocol !== 'https:' || url.origin !== origin || url.username || url.password ||
      url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '[::1]') {
    deny(503, 'configuration_unavailable');
  }
  return Object.freeze({projectId: PROJECT, databaseId: DATABASE, origin});
}

// Reject duplicate security headers rather than relying on Node's merge rules.
function singleHeader(req, name) {
  const raw = req.rawHeaders;
  if (Array.isArray(raw)) {
    let count = 0;
    for (let i = 0; i < raw.length; i += 2) if (String(raw[i]).toLowerCase() === name) count++;
    if (count > 1) deny(400, 'invalid_request');
  }
  const value = req.headers?.[name];
  if (value === undefined) return undefined;
  if (typeof value !== 'string') deny(400, 'invalid_request');
  return value;
}

function validateRequest(req, config) {
  if (singleHeader(req, 'origin') !== config.origin) deny(403, 'origin_not_allowed');
  if (req.method === 'OPTIONS') {
    if (singleHeader(req, 'access-control-request-method') !== 'POST') deny(405, 'method_not_allowed');
    const requested = (singleHeader(req, 'access-control-request-headers') || '').toLowerCase()
      .split(',').map(s => s.trim()).filter(Boolean);
    if (!requested.includes('authorization') || requested.some(h => !['authorization', 'content-type'].includes(h))) {
      deny(403, 'headers_not_allowed');
    }
    return {preflight: true};
  }
  if (req.method !== 'POST') deny(405, 'method_not_allowed');
  if (req.url && req.url !== '/' && req.url !== '') deny(400, 'invalid_request');
  if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(singleHeader(req, 'content-type') || '')) {
    deny(415, 'json_required');
  }
  const encoding = singleHeader(req, 'content-encoding');
  if (encoding && encoding !== 'identity') deny(415, 'encoding_not_supported');
  const declared = singleHeader(req, 'content-length');
  if (declared !== undefined && (!/^\d+$/.test(declared) || Number(declared) > MAX_BODY_BYTES)) deny(413, 'body_too_large');
  if (!Buffer.isBuffer(req.rawBody)) deny(400, 'invalid_request');
  if (req.rawBody.length > MAX_BODY_BYTES) deny(413, 'body_too_large');
  let body;
  try { body = JSON.parse(req.rawBody.toString('utf8')); } catch { deny(400, 'invalid_json'); }
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length !== 1 ||
      !Object.hasOwn(body, 'roleKey') || typeof body.roleKey !== 'string' || !Object.hasOwn(ROLES, body.roleKey)) {
    deny(400, 'invalid_role_request');
  }
  const authorization = singleHeader(req, 'authorization') || '';
  const match = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/.exec(authorization);
  if (!match || Buffer.byteLength(match[1]) > MAX_TOKEN_BYTES) deny(401, 'sign_in_required');
  return {preflight: false, idToken: match[1], identity: ROLES[body.roleKey]};
}

function validateOperator(decoded) {
  if (!decoded || decoded.aud !== PROJECT || decoded.iss !== `https://securetoken.google.com/${PROJECT}` ||
      typeof decoded.uid !== 'string' || !decoded.uid || decoded.uid.length > 128 || decoded.sub !== decoded.uid ||
      decoded.uid.startsWith('mdxtest') || decoded.email !== OWNER_EMAIL || decoded.email_verified !== true ||
      decoded.firebase?.sign_in_provider !== 'google.com' || decoded.firebase?.tenant !== undefined) {
    deny(403, 'operator_not_allowed');
  }
  return decoded.uid;
}

function validateOperatorRecord(user, uid) {
  if (!user || user.uid !== uid || user.disabled !== false || user.email !== OWNER_EMAIL ||
      user.emailVerified !== true || user.tenantId ||
      !Array.isArray(user.providerData) || !user.providerData.some(p => p.providerId === 'google.com' && p.email === OWNER_EMAIL)) {
    deny(403, 'operator_not_allowed');
  }
}

function validateTestUser(user, identity) {
  const claims = user?.customClaims;
  if (!user || user.uid !== identity.uid || user.disabled !== false || user.tenantId ||
      !claims || claims.mydoxTest !== true || claims.testDatabase !== DATABASE || claims.role !== identity.role) {
    deny(403, 'test_role_unavailable');
  }
  // Unexpected claims require review rather than silently inheriting privileges
  // into the signed-in role. The seeded accounts have exactly these three claims.
  if (Object.keys(claims).some(k => !['mydoxTest', 'testDatabase', 'role'].includes(k))) {
    deny(403, 'test_role_unavailable');
  }
}

function roleClaims(identity, operatorUid, nowMs = Date.now()) {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) deny(503, 'temporarily_unavailable');
  return {mydoxTest: true, testDatabase: DATABASE, role: identity.role,
    cloudLab: true, labOperatorUid: operatorUid, labIssuedAt: nowMs, labExpiresAt: nowMs + LAB_SESSION_MS};
}

module.exports = {PROJECT, DATABASE, OWNER_EMAIL, SERVICE_ACCOUNT, MAX_BODY_BYTES, MAX_TOKEN_BYTES, LAB_SESSION_MS,
  FAMILIES, ROLES, PolicyError, configFromEnv, singleHeader, validateRequest,
  validateOperator, validateOperatorRecord, validateTestUser, roleClaims};
