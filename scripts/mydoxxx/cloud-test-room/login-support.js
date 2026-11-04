// Browser sign-in helpers for the private cloud test room. No Firebase imports
// here: this file is unit-tested in Node and must never touch tokens or storage.

/** An error whose message is written for the operator and safe to display. */
export function friendlyError(message) {
  return Object.assign(new Error(message), { userFacing: true });
}

export const OPEN_IN_BROWSER =
  'If no Google window appears, allow pop-ups for this site, or open the address in Chrome, Edge or Safari instead of an in-app or embedded browser.';

export const SLOW_POPUP_MESSAGE =
  'Google sign-in is still waiting for a result. If the Google window is open, finish sign-in there. ' + OPEN_IN_BROWSER;

export const STORAGE_BLOCKED_MESSAGE =
  'This browser is blocking the temporary storage that sign-in needs. Use a normal window of Chrome, Edge or Safari, allow site data for this page, then reload.';

const BY_CODE = {
  'auth/popup-blocked': 'Your browser blocked the Google sign-in window. Allow pop-ups for this site, then try again.',
  'auth/popup-closed-by-user': 'Sign-in was cancelled. You can try again.',
  'auth/cancelled-popup-request': 'Sign-in was cancelled. You can try again.',
  'auth/operation-not-supported-in-this-environment': 'This browser cannot open Google sign-in from here. ' + OPEN_IN_BROWSER,
  'auth/web-storage-unsupported': STORAGE_BLOCKED_MESSAGE,
  'auth/network-request-failed': 'Google sign-in could not reach the network. Check your internet connection and try again.',
  'auth/unauthorized-domain': 'This address is not approved for sign-in. Use https://mydoxxx-live-test.netlify.app/ exactly.',
  'auth/too-many-requests': 'Too many sign-in attempts. Wait a few minutes, then try again.',
  'auth/user-disabled': 'This account cannot be used for the test room.',
};

/** Text to show for a failed sign-in. Never echoes an unknown error's own message. */
export function signInMessage(error) {
  if (error && error.userFacing === true && typeof error.message === 'string') return error.message;
  const code = error && typeof error.code === 'string' ? error.code : '';
  return Object.hasOwn(BY_CODE, code) ? BY_CODE[code] : 'Google sign-in could not complete. Please try again.';
}

/**
 * Calls [onSlow] once if [work] is still pending after [ms]. Returns a cancel
 * function. Never cancels or alters [work] itself (an open popup keeps working).
 */
export function watchSlow(ms, onSlow, timers = { setTimeout, clearTimeout }) {
  // Detach the functions: browsers throw "Illegal invocation" if setTimeout is
  // called with this set to a helper object instead of the window.
  const { setTimeout: start, clearTimeout: stop } = timers;
  const id = start(onSlow, ms);
  return () => stop(id);
}
