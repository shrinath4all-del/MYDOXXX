const assert = require("assert");
const wallet = require("../wallet");
const { computeApply } = require("../chat_recharge");

const H = 60 * 60 * 1000;
const DAY = 24 * H;

// ---- client times are Indian time (no zone), server times end in Z
assert.strictEqual(
  wallet.istMs("2026-10-26T10:00:00"), Date.parse("2026-10-26T04:30:00Z"));
assert.strictEqual(
  wallet.istMs("2026-10-26T10:00:00.123456"), Date.parse("2026-10-26T04:30:00.123Z"));
assert.strictEqual(
  wallet.istMs("2026-10-26T04:30:00.000Z"), Date.parse("2026-10-26T04:30:00Z"));
assert.ok(Number.isNaN(wallet.istMs("")));

// ---- how many MedCoins a payment uses
assert.strictEqual(wallet.coinsToUse(500, 200, true), 200); // never more than the price
assert.strictEqual(wallet.coinsToUse(120, 200, true), 120); // all they have
assert.strictEqual(wallet.coinsToUse(120, 200, false), 0); // not asked
assert.strictEqual(wallet.coinsToUse(0, 200, true), 0);
assert.strictEqual(wallet.coinsToUse(99.9, 200, true), 99); // whole coins only

// ---- refund: 4 hours after the PATIENT's message, not after the payment
const P = "patient1";
const D = "doctor1";
const paid = Date.parse("2026-10-26T10:00:00Z");
const decide = (messages, nowMs) => wallet.chatRechargeDecision({
  messages, patientUid: P, providerUid: D, paidAtMs: paid, nowMs,
});

// the patient has not written since paying: nothing to answer, even 10 h on
assert.strictEqual(decide([], paid + 10 * H), "wait");

// the patient wrote 1 h after paying
const msgAt = paid + 1 * H;
const patientMsg = { senderUid: P, atMs: msgAt };
assert.strictEqual(decide([patientMsg], msgAt + 3 * H), "wait"); // 4 h not over
assert.strictEqual(decide([patientMsg], msgAt + 4 * H), "refund"); // 4 h over, no reply
assert.strictEqual(
  decide([patientMsg, { senderUid: D, atMs: msgAt + 1 * H }], msgAt + 6 * H),
  "answered");
// a reply after the 4 hours is too late
assert.strictEqual(
  decide([patientMsg, { senderUid: D, atMs: msgAt + 5 * H }], msgAt + 6 * H),
  "refund");
// the doctor's earlier message (before the patient wrote) does not count
assert.strictEqual(
  decide([{ senderUid: D, atMs: paid + 0.5 * H }, patientMsg], msgAt + 5 * H),
  "refund");
// messages from before the payment are ignored
assert.strictEqual(
  decide([{ senderUid: P, atMs: paid - 2 * H }], paid + 10 * H), "wait");
// only the FIRST message after paying starts the clock
assert.strictEqual(
  decide([patientMsg, { senderUid: P, atMs: msgAt + 3 * H }], msgAt + 4 * H),
  "refund");

// ---- what a paid recharge does to the chat
const end = Date.parse("2026-10-26T04:30:00Z"); // consultation ended
const plan = { days: 3, messages: 25 };

// first recharge, window already over: 3 days from now
let now = end + 30 * H;
let c = computeApply({}, plan, end, now);
assert.strictEqual(c.used, 0);
assert.strictEqual(c.bonus, 25);
assert.strictEqual(c.newEnd, now + 3 * DAY);

// recharged while the free 24 h still run: 3 days on top of the end
now = end + 10 * H;
c = computeApply({}, plan, end, now);
assert.strictEqual(c.newEnd, end + DAY + 3 * DAY);

// second recharge in the same window: messages and time add up
const chat = {
  accessEpoch: new Date(end).toISOString(),
  patientMsgsUsed: 40,
  bonusMsgs: 25,
  paidUntil: new Date(end + 4 * DAY).toISOString(),
};
now = end + 2 * DAY;
c = computeApply(chat, plan, end, now);
assert.strictEqual(c.used, 40);
assert.strictEqual(c.bonus, 50);
assert.strictEqual(c.newEnd, end + 4 * DAY + 3 * DAY);

// a later consultation starts a new window: old counters do not carry over
const later = end + 10 * DAY;
c = computeApply(chat, plan, later, later + H);
assert.strictEqual(c.used, 0);
assert.strictEqual(c.bonus, 25);
assert.strictEqual(c.newEnd, later + DAY + 3 * DAY);

// ---- the ₹200 single message: exactly one more message, a day for the reply
const single = { days: 1, messages: 1, single: true };
const usedUp = { accessEpoch: new Date(end).toISOString(), patientMsgsUsed: 10, bonusMsgs: 0 };
now = end + 2 * DAY; // the free 24 h are over
c = computeApply(usedUp, single, end, now);
assert.strictEqual(10 + c.bonus - c.used, 1, "one message left");
assert.strictEqual(c.bonus - c.bonusBefore, 1, "the refund takes back what was added");
assert.strictEqual(c.newEnd, now + DAY);
// free messages not used before the time ran out are kept (still one more at least)
c = computeApply({ ...usedUp, patientMsgsUsed: 4 }, single, end, now);
assert.strictEqual(c.bonus, 0);
assert.strictEqual(c.bonus - c.bonusBefore, 0);

console.log("All wallet and chat recharge function tests passed");
