/**
 * "Delete account" for every login (patient, doctor, nurse, technician,
 * therapist, care physician, hospital, ambulance, partner), the way
 * Facebook / Instagram do it:
 *
 *   1. requestAccountDeletion   the account is deactivated at once (hidden:
 *                               not bookable, not available, not online) and
 *                               scheduled for deletion in 30 days; the app
 *                               signs out.
 *   2. cancelAccountDeletion    logging in again within the 30 days and
 *                               choosing "Keep my account" restores it as it
 *                               was.
 *   3. purgeDeletedAccounts     every day: accounts whose 30 days are over
 *                               are deleted for good (deleteAccountData).
 *
 * Deleting for good removes the profile in every role collection (and its
 * sub-collections), users/{uid} (role, push tokens, notification history),
 * the profile photo and verification documents in Storage and their
 * fingerprints, and the sign-in itself. Bookings, duties and chats stay,
 * because the other side (doctor, hospital, patient) keeps its records.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const ROLE_COLLECTIONS = [
  "patients", "doctors", "hospitals", "ambulances", "technicians",
  "therapists", "nurses", "agencies", "care_physicians",
];
const GRACE_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;

/** What deactivating turns off (and keeping the account turns back on). */
// (partners are listed while `active`)
const HIDDEN = { isVerified: false, available: false, isOnline: false, active: false };

/** What deactivating writes on a profile [p]: hidden, and how it was. */
function hideFields(p) {
  const before = {};
  for (const k of Object.keys(HIDDEN)) before[k] = p[k] ?? null;
  return { ...HIDDEN, deletionPending: true, beforeDeletion: before };
}

/** What keeping the account writes: each field as it was ([del] = remove). */
function restoreFields(before, del) {
  const out = { deletionPending: del, beforeDeletion: del };
  for (const k of Object.keys(HIDDEN)) {
    const v = (before || {})[k];
    out[k] = v === null || v === undefined ? del : v;
  }
  return out;
}
exports.hideFields = hideFields;
exports.restoreFields = restoreFields;

/** The account's profiles, as references that exist. */
async function profilesOf(db, uid) {
  const refs = ROLE_COLLECTIONS.map((c) => db.collection(c).doc(uid));
  const snaps = await db.getAll(...refs);
  return snaps.filter((s) => s.exists);
}

/** Step 1: deactivate now, delete in 30 days. */
exports.requestAccountDeletion = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please log in again.");
  const db = admin.firestore();
  const now = Date.now();
  const deleteAfter = new Date(now + GRACE_DAYS * DAY_MS).toISOString();

  const batch = db.batch();
  for (const snap of await profilesOf(db, uid)) {
    // hidden, and how it was so "Keep my account" puts it back exactly
    batch.set(snap.ref, hideFields(snap.data()), { merge: true });
  }
  batch.set(db.collection("users").doc(uid), {
    deletion: { requestedAt: new Date(now).toISOString(), deleteAfter },
    // no pushes while deactivated
    fcmTokens: [],
  }, { merge: true });
  await batch.commit();
  logger.info("account deletion requested", { deleteAfter });
  return { deleteAfter };
});

/** Step 2: the user logged in again and keeps the account. */
exports.cancelAccountDeletion = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please log in again.");
  const db = admin.firestore();
  const del = admin.firestore.FieldValue.delete();

  const batch = db.batch();
  for (const snap of await profilesOf(db, uid)) {
    batch.set(snap.ref, restoreFields(snap.data().beforeDeletion, del), { merge: true });
  }
  batch.set(db.collection("users").doc(uid), { deletion: del }, { merge: true });
  await batch.commit();
  return { restored: true };
});

/** Deletes everything of [uid] for good. */
async function deleteAccountData(uid) {
  const db = admin.firestore();
  for (const snap of await profilesOf(db, uid)) {
    await db.recursiveDelete(snap.ref);
  }
  await db.recursiveDelete(db.collection("users").doc(uid));

  // its documents can be used by another account again
  const prints = await db.collection("document_fingerprints").where("uid", "==", uid).get();
  await Promise.all(prints.docs.map((d) => d.ref.delete()));

  try {
    const bucket = admin.storage().bucket();
    await bucket.deleteFiles({ prefix: `verification_docs/${uid}/` });
    await bucket.file(`profile_pics/${uid}.jpg`).delete({ ignoreNotFound: true });
  } catch (e) {
    logger.warn("account files not removed", { uid, error: e.message });
  }

  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
  }
}
exports.deleteAccountData = deleteAccountData;

/** Step 3: every day, delete the accounts whose 30 days are over. */
exports.purgeDeletedAccounts = onSchedule(
  { schedule: "every day 03:00", timeZone: "Asia/Kolkata" },
  async () => {
    const db = admin.firestore();
    const due = await db.collection("users")
      .where("deletion.deleteAfter", "<=", new Date().toISOString())
      .get();
    let deleted = 0;
    for (const doc of due.docs) {
      const role = (doc.data() || {}).role || "";
      try {
        await deleteAccountData(doc.id);
        // no phone number or name is kept: only that an account went
        await db.collection("deleted_accounts").add({
          role,
          deletedAt: new Date().toISOString(),
        });
        deleted++;
      } catch (e) {
        logger.error("account not deleted", { uid: doc.id, error: e.message });
      }
    }
    logger.info("deleted accounts purged", { due: due.size, deleted });
  },
);
