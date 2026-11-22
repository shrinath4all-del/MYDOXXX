// "Delete account" like Facebook / Instagram: deactivate now, keep restores
// everything exactly. Usage (in functions/): node test/delete_account_test.js
const assert = require("assert");
const { hideFields, restoreFields } = require("../delete_account");

const DEL = "<delete>";

// a verified, available doctor who asks to delete the account
const doctor = { name: "Asha", isVerified: true, available: true, isOnline: true };
const hidden = hideFields(doctor);
assert.strictEqual(hidden.isVerified, false, "not bookable while deactivated");
assert.strictEqual(hidden.available, false);
assert.strictEqual(hidden.isOnline, false);
assert.strictEqual(hidden.active, false, "partners drop out of lists too");
assert.strictEqual(hidden.deletionPending, true);
assert.deepStrictEqual(hidden.beforeDeletion,
  { isVerified: true, available: true, isOnline: true, active: null });

// "Keep my account": back exactly as it was
const back = restoreFields(hidden.beforeDeletion, DEL);
assert.strictEqual(back.isVerified, true);
assert.strictEqual(back.available, true);
assert.strictEqual(back.isOnline, true);
assert.strictEqual(back.active, DEL, "a field that was not there is removed again");
assert.strictEqual(back.deletionPending, DEL);
assert.strictEqual(back.beforeDeletion, DEL);

// an unverified provider stays unverified after keeping the account
const pending = restoreFields(hideFields({ isVerified: false }).beforeDeletion, DEL);
assert.strictEqual(pending.isVerified, false);

console.log("All delete account tests passed");
