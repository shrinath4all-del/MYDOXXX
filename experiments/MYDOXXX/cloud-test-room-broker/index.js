'use strict';
const {onRequest} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {PROJECT, SERVICE_ACCOUNT, configFromEnv} = require('./policy.cjs');
const {createHandler} = require('./handler.cjs');

let runtime;
function getRuntime() {
  if (!runtime) {
    const config = configFromEnv(process.env);
    // ADC under a dedicated runtime identity; no downloaded service-account key.
    const app = initializeApp({projectId: PROJECT, serviceAccountId: SERVICE_ACCOUNT}, 'mydoxxx-cloud-lab-broker');
    runtime = {config, auth: getAuth(app)};
  }
  return runtime;
}

exports.mintMyDoxLabRole = onRequest({
  region: 'us-central1', serviceAccount: SERVICE_ACCOUNT,
  invoker: 'public', cors: false,
  minInstances: 0, maxInstances: 1, memory: '256MiB', cpu: 1,
  concurrency: 10, timeoutSeconds: 30,
}, createHandler({getRuntime}));
