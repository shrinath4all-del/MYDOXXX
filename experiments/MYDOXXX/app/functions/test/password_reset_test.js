const assert = require("assert");
const { freshness } = require("../password_reset");

const now = Date.UTC(2026, 10, 23, 12, 0);
const min = 60 * 1000;
assert.deepStrictEqual(freshness(now - 5 * min, now), { ok: true, expired: false, minutesLeft: 10 });
assert.deepStrictEqual(freshness(now - 14.5 * min, now).ok, true);
assert.deepStrictEqual(freshness(now - 15 * min, now), { ok: false, expired: true, minutesLeft: 0 });
assert.deepStrictEqual(freshness(now - 60 * min, now).expired, true);
// a link sent before this check existed: left to Firebase's own expiry
assert.deepStrictEqual(freshness(NaN, now).ok, true);
console.log("password_reset tests passed");
