// Push notifications for every request popup: hospital, doctor, ambulance and
// patient. The apps already show popups while open; these pushes reach the
// user when the app is closed or in the background. Tapping a notification
// opens the app, where the pending popup is shown as usual.
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const db = admin.firestore();
const SOS = "SOS Emergency Pipeline";

// ------------------------------------------------------------------ helpers

/** Device times are saved without a zone; the app is used in India. */
const ms = (v) => {
  if (!v) return NaN;
  if (typeof v.toDate === "function") return v.toDate().getTime();
  const t = String(v);
  return Date.parse(/[zZ]|[+-]\d\d:?\d\d$/.test(t) ? t : t + "+05:30");
};

const km = (lat1, lon1, lat2, lon2) => {
  const R = 6371;
  const rad = (x) => (x * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};

const str = (o) =>
  Object.fromEntries(Object.entries(o).map(([k, v]) => [k, String(v ?? "")]));

/** Kept in each account's notification list this long. */
const HISTORY_DAYS = 60;

/**
 * Saves the notification in users/{uid}/notifications so the bell of every
 * login lists it (with the unread count), even when the push never reached
 * a phone. Chat messages are left out: the Chat tab lists those.
 */
async function saveHistory(uids, { title, body, data }) {
  if (data.type === "chat") return;
  // never stops the push itself
  try {
    const batch = db.batch();
    const expireAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + HISTORY_DAYS * 24 * 60 * 60 * 1000
    );
    for (const uid of uids) {
      batch.set(db.collection("users").doc(uid).collection("notifications").doc(), {
        title: String(title || ""),
        body: String(body || ""),
        type: String(data.type || ""),
        data: str(data),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expireAt, // a Firestore TTL policy on this field clears old ones
      });
    }
    await batch.commit();
  } catch (e) {
    console.error("saving notification history failed", e.code, e.message);
  }
}

/** Sends a notification to every device of each uid; drops dead tokens. */
async function notify(uids, { title, body, data = {} }) {
  const unique = [...new Set((uids || []).filter(Boolean))];
  if (unique.length === 0) {
    console.log("notify skipped (no recipients):", title);
    return;
  }
  await saveHistory(unique, { title, body, data });
  const snaps = await db.getAll(...unique.map((u) => db.collection("users").doc(u)));
  for (const snap of snaps) {
    const tokens = (snap.data() && snap.data().fcmTokens) || [];
    if (tokens.length === 0) {
      console.log(`NO PUSH TOKEN for user ${snap.id} (never allowed notifications / never opened the app on a phone): ${title}`);
      continue;
    }
    try {
      const res = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: str(data),
        android: {
          priority: "high",
          notification: { channelId: "emergency_alerts", sound: "default" },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      });
      console.log(`push "${title}" -> user ${snap.id}: ${res.successCount} sent, ${res.failureCount} failed`);
      const dead = [];
      res.responses.forEach((r, i) => {
        if (r.error) console.error("push error", snap.id, r.error.code, r.error.message);
        const code = r.error && r.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          dead.push(tokens[i]);
        }
      });
      if (dead.length) {
        await snap.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead) });
      }
    } catch (e) {
      console.error("sendEachForMulticast failed", snap.id, e.code, e.message);
    }
  }
}

async function busyDoctors() {
  const active = new Set([
    "Confirmed", "In Progress", "Pending Ambulance Dispatch",
    "Ambulance Dispatched", "Patient Picked Up",
  ]);
  const snap = await db.collection("appointments").where("isUrgentEmergency", "==", true).get();
  const out = new Set();
  snap.forEach((d) => {
    const a = d.data();
    if (active.has(a.status) && a.doctorUid) out.add(a.doctorUid);
  });
  return out;
}

async function busyAmbulances() {
  const snap = await db.collection("appointments").where("consultationType", "==", SOS).get();
  const out = new Set();
  snap.forEach((d) => {
    const a = d.data();
    if ((a.status === "Ambulance Dispatched" || a.status === "Patient Picked Up") && a.assignedAmbulanceUid) {
      out.add(a.assignedAmbulanceUid);
    }
  });
  return out;
}

// ---------------------------------------------- who is being asked right now
// Mirrors the app's radius rules so a push goes out exactly when the popup
// would first appear for that provider.

function isExpired(a) {
  if (a.consultationType === SOS) {
    const open = ["Pending Hospital Acceptance", "Pending Doctor Assignment", "Pending Ambulance Dispatch"];
    if (!open.includes(a.status)) return false;
    const end = ms(a.sosExpiresAt) || ms(a.createdAt) + 5 * 60000;
    return Date.now() > end;
  }
  if (a.autoExpire !== true || a.doctorAcceptedAt) return false;
  if (!["Pending Emergency", "Pending Doctor Assignment", "Broadcasted", "Declined"].includes(a.status)) return false;
  const start = ms(a.broadcastedAt) || ms(a.createdAt) + 60000;
  return Date.now() > start + 2 * 60000;
}

const steps = (start, stepMs, offsetMs = 0) =>
  Math.min(8, 4 + 2 * Math.floor(Math.max(0, Date.now() - start - offsetMs) / stepMs));

// ------------------------------------------- nurse / technician / therapist

const PROVIDER_COLLECTIONS = { nurse: "nurses", technician: "technicians", therapist: "therapists" };

/** 'nurse' | 'technician' | 'therapist' for a provider booking, else null. */
function providerRole(a) {
  if (a.roleTarget && PROVIDER_COLLECTIONS[a.roleTarget]) return a.roleTarget;
  if (a.isNurseRequest) return "nurse";
  if (a.isTechnicianRequest) return "technician";
  if (a.isTherapistRequest) return "therapist";
  return null;
}

/** Same as the app's providerServesArea ("Wakad" covers "Wakad, Pune"). */
function servesArea(areas, location) {
  const full = String(location || "").toLowerCase();
  const primary = full.split(",")[0].trim();
  if (!primary) return false;
  return areas.some((raw) => {
    const area = String(raw).trim().toLowerCase();
    if (!area) return false;
    return full.includes(area) || (primary.length >= 4 && area.includes(primary));
  });
}

/** What the visit is called for each kind of provider. */
const visitWord = (a) => ({
  nurse: "nursing visit",
  technician: "lab test visit",
  therapist: "therapy session",
}[providerRole(a)] || "consultation");

/** "Dr. Asha" for doctors, just the name for nurses / technicians / physios. */
const providerName = (a) => {
  const name = String(a.doctorName || "").trim();
  if (providerRole(a)) return name || "Your provider";
  return name ? `Dr. ${name.replace(/^Dr\.?\s*/i, "")}` : "The doctor";
};

/** { role, uids } currently allowed to see the request, or null. */
/** uid -> km from (lat,lng) using each provider's live saved position. */
async function liveKm(collection, stored, lat, lng) {
  const uids = Object.keys(stored || {});
  const out = {};
  if (uids.length === 0 || lat == null || lng == null) return { ...stored };
  const snaps = await db.getAll(...uids.map((u) => db.collection(collection).doc(u)));
  snaps.forEach((s) => {
    const d = s.data() || {};
    out[s.id] =
      d.latitude != null && d.longitude != null
        ? km(lat, lng, d.latitude, d.longitude)
        : stored[s.id];
  });
  return out;
}

async function audience(a) {
  if (isExpired(a)) return null;

  // Nurse / technician / therapist request open to everyone (a provider
  // declined, or "any physio"): the same providers the app lists it for.
  const role = providerRole(a);
  if (role && a.status === "Broadcasted" && a.isBroadcast === true) {
    const declined = new Set(a.declinedBy || []);
    // physio agency window: only the agency physios it was offered to
    if (role === "therapist" && a.routingStage === "team" && ms(a.agencyOfferExpiresAt) > Date.now()) {
      const offered = (Array.isArray(a.agencyOfferedTo) ? a.agencyOfferedTo : [])
        .filter((u) => !declined.has(u));
      // still online now (they may have gone offline since the offer)
      const snaps = offered.length
        ? await db.getAll(...offered.map((u) => db.collection("therapists").doc(u))) : [];
      return { role, uids: snaps.filter((s) => (s.data() || {}).isOnline !== false).map((s) => s.id) };
    }
    const snap = await db.collection(PROVIDER_COLLECTIONS[role]).get();
    const uids = [];
    snap.forEach((d) => {
      const p = d.data();
      if (declined.has(d.id) || p.isOnline === false) return;
      const areas = Array.isArray(p.preferredLocations) ? p.preferredLocations : [];
      if (areas.length && !servesArea(areas, a.locationName)) return;
      uids.push(d.id);
    });
    return { role, uids };
  }

  // Emergency Help: doctors
  if (a.consultationType === SOS && a.status === "Pending Doctor Assignment" && a.sosDoctorCandidatesKm) {
    const start = ms(a.doctorStageStartedAt);
    if (!start) return null;
    const preferred = a.preferredDoctorUids || [];
    const elapsed = Date.now() - start;
    if (preferred.length && elapsed < 60000) return { role: "doctor", uids: preferred };
    const radius = steps(start, 60000, preferred.length ? 60000 : 0);
    // doctors' LIVE position to the assigned hospital
    const live = await liveKm("doctors", a.sosDoctorCandidatesKm, a.assignedHospitalLat, a.assignedHospitalLng);
    const uids = Object.entries(live).filter(([, d]) => d != null && d <= radius).map(([u]) => u);
    return { role: "doctor", uids };
  }

  // Emergency Help: ambulances (measured from the patient)
  if (a.consultationType === SOS && a.status === "Pending Ambulance Dispatch" && a.sosAmbulanceCandidatesKm) {
    const start = ms(a.ambulanceStageStartedAt);
    if (!start) return null;
    const radius = steps(start, 60000);
    const declined = a.declinedAmbulanceUids || [];
    // ambulances' LIVE position to the patient's live location
    const live = await liveKm("ambulances", a.sosAmbulanceCandidatesKm, a.patientLat, a.patientLng);
    const uids = Object.entries(live)
      .filter(([u, d]) => d != null && d <= radius && !declined.includes(u))
      .map(([u]) => u);
    return { role: "ambulance", uids };
  }

  // Book Doctor urgent request: 4 km, 6 km after 30 s, 8 km after 60 s
  if (a.autoExpire === true && a.candidateDistancesKm && ["Broadcasted", "Pending Emergency"].includes(a.status)) {
    const start = ms(a.broadcastedAt) || ms(a.createdAt);
    const radius = steps(start, 30000);
    const declined = a.declinedBy || [];
    const uids = Object.entries(a.candidateDistancesKm)
      .filter(([u, d]) => d <= radius && !declined.includes(u))
      .map(([u]) => u);
    return { role: "doctor", uids };
  }
  return null;
}

/** Pushes to providers who have newly become eligible, once each. */
async function notifyAudience(ref, a) {
  const aud = await audience(a);
  if (!aud || aud.uids.length === 0) return;
  const already = new Set(a.pushedUids || []);
  // busy: doctors / ambulances on an emergency (not nurses, technicians, physios)
  const busy = aud.role === "ambulance" ? await busyAmbulances()
    : aud.role === "doctor" ? await busyDoctors() : new Set();
  let fresh = aud.uids.filter((u) => !already.has(u) && !busy.has(u));
  // an offline doctor gets no requests or emergency calls
  if (aud.role === "doctor" && fresh.length) {
    const docs = await db.getAll(...fresh.map((u) => db.collection("doctors").doc(u)));
    const offline = new Set(docs.filter((d) => (d.data() || {}).isOnline === false).map((d) => d.id));
    fresh = fresh.filter((u) => !offline.has(u));
  }
  if (fresh.length === 0) return;

  const isSos = a.consultationType === SOS;
  const category = a.emergencyCategory || a.doctorCategory || "Emergency";
  let title;
  let body;
  if (PROVIDER_COLLECTIONS[aud.role]) {
    title = { nurse: "New nursing request", technician: "New lab test request", therapist: "New therapy request" }[aud.role];
    const when = a.time ? ` · ${a.date || ""} ${a.time}`.trimEnd() : "";
    const what = a.therapyName || a.testName || a.consultationType || "";
    body = `${a.patientName || "A patient"}${what ? ` · ${what}` : ""}${a.locationName ? ` · ${String(a.locationName).split(",")[0]}` : ""}${when}. Open the app to accept.`;
  } else if (aud.role === "ambulance") {
    title = "🚑 Ambulance dispatch request";
    body = `${a.patientName || "A patient"} needs an ambulance${a.assignedHospitalName ? ` to ${a.assignedHospitalName}` : ""}.`;
  } else if (isSos) {
    title = "🚨 Emergency doctor request";
    body = `${a.patientName || "A patient"} needs an emergency ${category} doctor${a.assignedHospitalName ? ` at ${a.assignedHospitalName}` : ""}.`;
  } else {
    title = "🚨 Urgent doctor request";
    body = `${a.patientName || "A patient"} needs an urgent ${category} consultation nearby.`;
  }
  await notify(fresh, { title, body, data: { type: "request", appointmentId: ref.id } });
  await ref.update({ pushedUids: admin.firestore.FieldValue.arrayUnion(...fresh) });
}

/** SOS: hospitals within 4 km of the patient (fixed radius). */
async function notifyHospitals(ref, a) {
  if (a.patientLat == null || a.patientLng == null) return;
  // 4 km first, 6 km after a minute, 8 km after two (from the request)
  const radius = steps(ms(a.createdAt) || Date.now(), 60000);
  const already = new Set(a.pushedUids || []);
  const declined = new Set(a.declinedHospitalUids || []);
  const snap = await db.collection("hospitals").get();
  const uids = [];
  snap.forEach((d) => {
    const h = d.data();
    if (h.isVerified !== true || h.latitude == null || h.longitude == null) return;
    if (already.has(d.id) || declined.has(d.id)) return;
    if (km(a.patientLat, a.patientLng, h.latitude, h.longitude) <= radius) uids.push(d.id);
  });
  if (uids.length === 0) return;
  await notify(uids, {
    title: "🚨 SOS emergency nearby",
    body: `${a.patientName || "A patient"} needs help (${a.emergencyCategory || "Emergency"}). Open the app to accept.`,
    data: { type: "request", appointmentId: ref.id },
  });
  await ref.update({ pushedUids: admin.firestore.FieldValue.arrayUnion(...uids) });
}

// ------------------------------------------------------ status change texts

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

const patientText = (a) => ({
  "Pending Doctor Assignment": a.consultationType === SOS
    ? ["Hospital accepted", `${a.assignedHospitalName || "A hospital"} accepted your emergency. Finding a doctor…`]
    : null,
  "Pending Ambulance Dispatch": ["Doctor accepted", `Dr. ${a.doctorName || ""} accepted. Arranging your ambulance…`],
  Confirmed: a.consultationType === SOS
    ? ["Doctor accepted", `Dr. ${a.doctorName || ""} is waiting at ${a.assignedHospitalName || "the hospital"}.`]
    : ["Request accepted", `${providerName(a)} accepted your ${visitWord(a)} request.${a.paymentStatus === "pending" ? " Please pay in My Bookings to confirm." : ""}`],
  "Ambulance Dispatched": [
    "Ambulance on the way",
    `${a.assignedAmbulanceDriver || "Driver"} (${a.assignedVehicleNumber || "ambulance"}) is coming to you. Keep your OTP ready.`,
  ],
  "Patient Picked Up": ["You are on the way", "You have been picked up. Share your OTP with the hospital on arrival."],
  "In Progress": [cap(visitWord(a)) + " started", `Your ${visitWord(a)} has started.`],
  Completed: [cap(visitWord(a)) + " completed", `Your ${visitWord(a)} is complete. Please rate your experience.`],
});

async function onStatusChange(ref, before, a) {
  const data = { type: "status", appointmentId: ref.id };

  // ran out of time after a hospital / doctor had accepted
  if (a.status === "Expired") {
    await notify([a.patientUid], {
      title: "Emergency request closed",
      body: "We could not arrange everything in time, so your request was closed. Please call 108 or try again.",
      data,
    });
    await notify([a.doctorUid, a.assignedHospitalUid].filter((u) => u && u !== a.patientUid), {
      title: "Emergency closed",
      body: `The emergency for ${a.patientName || "the patient"} ran out of time and was closed.`,
      data,
    });
    return;
  }

  // patient
  const text = patientText(a)[a.status];
  if (text && a.patientUid) {
    await notify([a.patientUid], { title: text[0], body: text[1], data });
  }

  if (a.consultationType === SOS) {
    // hospital
    if (a.assignedHospitalUid) {
      if (a.status === "Pending Ambulance Dispatch") {
        await notify([a.assignedHospitalUid], {
          title: "Doctor assigned",
          body: `Dr. ${a.doctorName || ""} will attend ${a.patientName || "the patient"}.`,
          data,
        });
      } else if (a.status === "Ambulance Dispatched") {
        await notify([a.assignedHospitalUid], {
          title: "Ambulance dispatched",
          body: `${a.assignedVehicleNumber || "An ambulance"} is picking up ${a.patientName || "the patient"}.`,
          data,
        });
      } else if (a.status === "Patient Picked Up") {
        await notify([a.assignedHospitalUid], {
          title: "Patient on the way",
          body: `${a.patientName || "The patient"} is arriving. Enter the patient's OTP on arrival.`,
          data,
        });
      }
    }
    // doctor
    if (a.doctorUid) {
      if (a.status === "Patient Picked Up") {
        await notify([a.doctorUid], {
          title: "Patient on the way",
          body: `${a.patientName || "The patient"} is being brought to ${a.assignedHospitalName || "the hospital"}.`,
          data,
        });
      } else if (a.status === "In Progress") {
        await notify([a.doctorUid], {
          title: "Patient has arrived",
          body: `${a.patientName || "The patient"} reached ${a.assignedHospitalName || "the hospital"}. Start treatment.`,
          data,
        });
      }
    }
  }
}

// ----------------------------------------------------------------- triggers

exports.notifyAppointment = onDocumentWritten("appointments/{id}", async (event) => {
  const before = event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const ref = event.data.after.ref;

  // closed / erased before anyone accepted
  if (before && !after) {
    const open = ["Pending Hospital Acceptance", "Pending Doctor Assignment", "Pending Ambulance Dispatch", "Pending Emergency", "Broadcasted"];
    // (a request the patient cancelled himself needs no "closed" message)
    if (open.includes(before.status) && !before.doctorAcceptedAt && before.patientUid && !before.cancelledByPatient) {
      await notify([before.patientUid], {
        title: "Request closed",
        body: "No one could accept your request in time. Please try again or call 108 for emergencies.",
        data: { type: "closed" },
      });
    }
    return;
  }
  if (!after) return;

  // new request
  if (!before) {
    if (after.consultationType === SOS && after.status === "Pending Hospital Acceptance") {
      await notifyHospitals(ref, after);
      return;
    }
    // a doctor was picked directly (urgent, home visit or scheduled booking);
    // an offline nurse / technician / therapist gets no request push
    const pickedRole = providerRole(after);
    const pickedOffline = pickedRole && after.doctorUid && ((await db
      .collection(PROVIDER_COLLECTIONS[pickedRole]).doc(after.doctorUid).get()).data() || {}).isOnline === false;
    if (after.doctorUid && !pickedOffline) {
      const urgent = after.isUrgentEmergency === true;
      const when = after.time ? `${after.date || ""} ${after.time}`.trim() : "";
      await notify([after.doctorUid], {
        title: providerRole(after)
          ? (urgent ? "🚨 Urgent " : "New ") + visitWord(after) + " request"
          : urgent ? "🚨 Urgent patient request" : after.status === "Pending Home Visit" ? "Home visit request" : "New appointment booked",
        body: `${after.patientName || "A patient"}${when ? ` · ${when}` : ""}${after.consultationType ? ` · ${after.consultationType}` : ""}`,
        data: { type: "request", appointmentId: ref.id },
      });
      await ref.update({ pushedUids: admin.firestore.FieldValue.arrayUnion(after.doctorUid) });

      // scheduled booking done: confirm it to the patient as well
      if (!urgent && after.status === "Confirmed" && after.patientUid) {
        await notify([after.patientUid], {
          title: "Booking confirmed ✅",
          body: `Your appointment with Dr. ${after.doctorName || ""} is booked${when ? ` for ${when}` : ""}.`,
          data: { type: "status", appointmentId: ref.id },
        });
      }
    }
    await notifyAudience(ref, after);
    return;
  }

  // status moved on
  if (before.status !== after.status) {
    await onStatusChange(ref, before, after);
    await notifyAudience(ref, after);
  }
});

/** A hospital or doctor already accepted part of the request. */
const partlyAccepted = (a) => !!a.doctorAcceptedAt || !!a.assignedHospitalUid;

/**
 * Closes a request that ran out of time. Nobody accepted: deleted (as the
 * app does). A hospital or doctor already accepted: kept as 'Expired' so the
 * history stays and everyone involved is told (see onStatusChange).
 */
async function closeExpired(ref) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || !isExpired(snap.data())) return;
    const a = snap.data();
    if (partlyAccepted(a)) {
      tx.update(ref, {
        status: "Expired",
        expiredStage: a.status,
        expiredAt: new Date().toISOString(),
      });
    } else {
      tx.delete(ref);
    }
  });
}

/**
 * Every minute (and again after 30 s): close requests that ran out of time
 * (the patient is told by notifyAppointment), widen the search for waiting
 * requests and notify the providers who have just come into range.
 */
exports.widenRequestSearch = onSchedule(
  { schedule: "every 1 minutes", timeoutSeconds: 120 },
  async () => {
    const sweep = async () => {
      const snap = await db
        .collection("appointments")
        .where("status", "in", [
          "Broadcasted", "Pending Emergency", "Pending Doctor Assignment",
          "Pending Ambulance Dispatch", "Pending Hospital Acceptance", "Declined",
        ])
        .get();
      for (const d of snap.docs) {
        try {
          // Not fully arranged in time (SOS: hospital + doctor + ambulance
          // within 5 min; urgent doctor request: 2 min): erase the request.
          // The delete trigger tells the patient it was closed.
          if (isExpired(d.data())) {
            await closeExpired(d.ref);
            console.log("expired request deleted", d.id);
            continue;
          }
          const data = d.data();
          if (data.consultationType === SOS && data.status === "Pending Hospital Acceptance") {
            await notifyHospitals(d.ref, data); // widening 4 -> 6 -> 8 km
          } else {
            await notifyAudience(d.ref, data);
          }
        } catch (e) {
          console.error("sweep failed for", d.id, e);
        }
      }
    };
    await sweep();
    await new Promise((r) => setTimeout(r, 30000));
    await sweep();
  }
);

// used by care_physician.js
exports.notify = notify;

const ROLE_LABELS = {
  patient: "Patient", doctor: "Doctor", nurse: "Nurse",
  technician: "Technician", therapist: "Therapist",
};

/**
 * A chat message was sent: push it to the other person in the chat.
 * Chat ids are "<patientUid>_<providerUid>" (Firebase uids have no "_").
 */
exports.notifyChatMessage = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const m = event.data && event.data.data();
  if (!m || !m.senderUid) return;
  const parts = String(event.params.chatId).split("_");
  if (parts.length !== 2 || !parts.includes(m.senderUid)) return;
  const recipient = parts.find((p) => p !== m.senderUid);
  if (!recipient) return;

  const sender = await db.collection("users").doc(m.senderUid).get();
  const role = ROLE_LABELS[(sender.data() && sender.data().role) || ""] || "";
  const kind = m.type || "text";
  const body =
    kind === "image" ? "📷 Photo" :
    kind === "text" || !m.mediaUrl ? String(m.text || "").slice(0, 140) :
    `📎 ${String(m.fileName || "Attachment")}`.slice(0, 140);

  await notify([recipient], {
    title: m.senderName ? String(m.senderName) : "New message",
    body: body || "New message",
    data: {
      type: "chat",
      chatId: event.params.chatId,
      senderUid: m.senderUid,
      senderName: m.senderName || "",
      senderRole: role,
    },
  });
});
