'use strict';
const {PROJECT, DATABASE, PolicyError, singleHeader, validateRequest, validateOperator,
  validateOperatorRecord, validateTestUser, roleClaims} = require('./policy.cjs');

// Dependency injection keeps tests offline: the only production calls are Auth
// verifyIdToken/getUser/createCustomToken. There are no database writes or logs.
function createHandler({getRuntime, now = Date.now}) {
  return async function broker(req, res) {
    res.setHeader('Cache-Control', 'no-store, private, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Vary', 'Origin');
    try {
      const {config, auth} = getRuntime();
      if (singleHeader(req, 'origin') === config.origin) res.setHeader('Access-Control-Allow-Origin', config.origin);
      const request = validateRequest(req, config);
      if (request.preflight) {
        res.setHeader('Access-Control-Allow-Methods', 'POST');
        res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
        return res.status(204).end();
      }
      let decoded;
      try { decoded = await auth.verifyIdToken(request.idToken, true); }
      catch { throw new PolicyError(401, 'sign_in_required'); }
      const operatorUid = validateOperator(decoded);
      const operator = await auth.getUser(operatorUid);
      validateOperatorRecord(operator, operatorUid);
      const user = await auth.getUser(request.identity.uid);
      validateTestUser(user, request.identity);
      const claims = roleClaims(request.identity, operatorUid, now());
      const customToken = await auth.createCustomToken(request.identity.uid, claims);
      if (typeof customToken !== 'string' || !customToken) throw new Error('Invalid token result');
      return res.status(200).json({projectId: PROJECT, databaseId: DATABASE,
        ...request.identity, customToken, labIssuedAt: claims.labIssuedAt, labExpiresAt: claims.labExpiresAt});
    } catch (error) {
      // Never emit SDK errors: they may contain token, email or request details.
      const known = error instanceof PolicyError;
      return res.status(known ? error.status : 503).json({error: known ? error.code : 'temporarily_unavailable'});
    }
  };
}

module.exports = {createHandler};
