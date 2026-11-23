// Push notifications for care physicians: hospital / agency shifts and
// patients' home visits (shifts/{id}), and interest in full-time jobs.
//
//   new shift / home visit   -> care physicians it fits (same rules as the
//                               app's Shifts tab); a home visit goes to the
//                               serving agencies' doctors first for 15 min,
//                               and the agencies are told it was offered
//   agency window ended      -> everyone else it fits (sweep)
//   claimed                  -> poster (patient / hospital / agency) and the
//                               doctor's agency, with the reach-by time
//   1 h before the start     -> doctor reminder (sweep)
//   arrived / done / no-show / cancelled -> the people involved
//   interest in a job        -> the hospital / agency that posted it
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const { notify } = require("./notifications");
const { enforceDutyRate: enforceCareDutyRate } = require("./care_duty_pricing");

const db = admin.firestore();
const LATE_AFTER_MIN = 45; // travel buffer, as in the app
const GATED = new Set(["intubation", "central_line", "ventilator", "acls", "lumbar_puncture"]);
const IST = "+05:30";

// ------------------------------------------------------------------ times

/** Device times are saved without a zone; the app is used in India. */
const parseLocal = (v) => {
  if (!v) return NaN;
  if (typeof v.toDate === "function") return v.toDate().getTime();
  const s = String(v);
  return Date.parse(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + IST);
};

const startMs = (s) => (s.date && s.start ? Date.parse(`${s.date}T${s.start}:00${IST}`) : NaN);

/** A full-time job takes care physicians until the end of its start day; a shift until it starts. */
const closesMs = (s) =>
  s.rotation === true && s.date ? Date.parse(`${s.date}T00:00:00${IST}`) + 86400000 : startMs(s);

/** "6:45 PM" in India time. */
const clock = (ms) =>
  Number.isFinite(ms)
    ? new Date(ms).toLocaleTimeString("en-IN", {
        timeZone: "Asia/Kolkata", hour: "numeric", minute: "2-digit", hour12: true,
      }).toUpperCase()
    : "";

/** "Thu 8 Oct, 6:00 PM" */
const when = (s) => {
  const ms = startMs(s);
  if (!Number.isFinite(ms)) return `${s.date || ""} ${s.start || ""}`.trim();
  const day = new Date(ms).toLocaleDateString("en-IN", {
    timeZone: "Asia/Kolkata", weekday: "short", day: "numeric", month: "short",
  });
  return `${day}, ${clock(ms)}`;
};

const reachBy = (s) => clock(startMs(s) + LATE_AFTER_MIN * 60000);

// --------------------------------------------------------------- matching

const list = (v) => (Array.isArray(v) ? v.map(String) : []);

/** Same as FirestoreService.providerServesArea ("Wakad" covers "Wakad, Pune"). */
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

const isVisit = (s) => s.postedBy === "patient";

/**
 * A hospital pays the master-table rate for the duty type
 * (care_duty_rates/{ward|icu|specialty}); the care physician gets the rate
 * minus the platform margin. The app writes these numbers too, but the
 * server is the authority: a price changed in a modified app is put right.
 */
async function enforceDutyRate(ref, s) {
  return enforceCareDutyRate(db, ref, s);
}

const agencyWindowOpen = (s, now = Date.now()) =>
  (list(s.offerAgencyIds).length > 0 || s.agencyFirst === true) && now < parseLocal(s.agencyOfferUntil);

/** Would this care physician see the shift and be able to claim it? */
function fits(s, p) {
  if (p.available === false) return false;
  if (s.dutyType === "icu" && p.isVerified !== true) return false; // ICU: verified only
  const types = list(p.dutyTypes);
  if (types.length && s.dutyType && !types.includes(s.dutyType)) return false;
  const areas = list(p.areas);
  if (areas.length && s.area && !servesArea(areas, s.area)) return false;
  const mine = list(p.procedures);
  for (const need of list(s.procedures)) {
    if (!mine.includes(need)) return false;
    if (GATED.has(need) && p.isVerified !== true) return false;
  }
  return true;
}

/**
 * Care physicians to tell about an open shift now: during the agency window
 * only the offered agencies' doctors, afterwards everyone it fits.
 */
async function audience(s) {
  const now = Date.now();
  if (s.status !== "open" || !(closesMs(s) > now)) return [];
  const declined = new Set(list(s.declinedBy));
  const offered = list(s.offerUids);
  if (offered.length) {
    // a patient's home visit: only the care physicians who do the service,
    // serve the area and are free then (chosen when the patient asked)
    return offered.filter((u) => !declined.has(u));
  }
  const window = agencyWindowOpen(s, now);
  const agencies = new Set(list(s.offerAgencyIds));
  const snap = await db.collection("care_physicians").get();
  const uids = [];
  snap.forEach((d) => {
    const p = d.data();
    if (declined.has(d.id)) return;
    if (window) {
      // a hospital's shift: any agency doctor; a patient's visit: the offered agencies
      if (s.agencyFirst === true) {
        if (!p.agencyId) return;
      } else if (!agencies.has(String(p.agencyId || ""))) return;
    }
    if (fits(s, p)) uids.push(d.id);
  });
  return uids;
}

function offerText(s) {
  // the care physician is told what he earns, never what the hospital pays
  const earn = Number(s.doctorPay) || Number(s.pay);
  const pay = earn ? ` · ₹${earn.toLocaleString("en-IN")}` : "";
  if (isVisit(s)) {
    return {
      title: "🏠 New home visit",
      body: `${s.serviceName || "Home visit"} · ${s.area || ""} · ${when(s)}${pay}. Open the app to accept.`,
    };
  }
  return {
    title: s.urgent ? "🚨 Urgent shift open" : "New shift open",
    body: `${s.hospitalName || "Hospital"} · ${when(s)}${pay}`,
  };
}

/** Pushes the open shift to doctors who have newly become eligible, once. */
async function offer(ref, s) {
  const already = new Set(list(s.pushedUids));
  const fresh = (await audience(s)).filter((u) => !already.has(u));
  if (fresh.length === 0) return;
  const { title, body } = offerText(s);
  await notify(fresh, { title, body, data: { type: "care_shift", shiftId: ref.id } });
  await ref.update({ pushedUids: admin.firestore.FieldValue.arrayUnion(...fresh) });
}

// ---------------------------------------------------------- status changes

/** Login that posted the shift (the admin board has no phone). */
const posterUid = (s) => (s.posterId && s.posterId !== "admin" ? String(s.posterId) : null);

async function onStatusChange(id, before, s) {
  const data = { type: "care_shift", shiftId: id };
  const doctor = s.claimedByName || "The doctor";
  // agencies follow their duties, not patients' home visits
  const agency = isVisit(s) ? null : s.claimedAgencyId || s.agencyId;

  // a hospital's request accepted by an agency doctor: the agency decides
  if (s.status === "pending_agency" && before.status === "open") {
    if (s.pendingAgencyId) {
      await notify([s.pendingAgencyId], {
        title: "Approval needed",
        body: `${doctor} accepted ${s.hospitalName || "a hospital"}'s request for ${when(s)}. Approve to allocate.`,
        data,
      });
    }
    return;
  }

  // a care physician was placed in a full-time job on this shift's time: it
  // opens again for other care physicians, and the hospital is told
  if (s.status === "open" && before.status === "claimed") {
    const who = s.reopenedFrom || before.claimedByName || "The care physician";
    if (posterUid(s)) {
      await notify([posterUid(s)], {
        title: "Your shift is open again",
        body: `${who} moved to a full-time job and can no longer take ${s.hospitalName || "your"} shift on ${when(s)}. It is offered to other care physicians now.`,
        data,
      });
    }
    if (before.claimedBy) {
      await notify([before.claimedBy], {
        title: "Shift released",
        body: `${s.hospitalName || "A"} shift on ${when(s)} was released because you were placed in a full-time job at that time.`,
        data,
      });
    }
    await offer(db.collection("shifts").doc(id), s);
    return;
  }

  // the agency did not send him: the request is open again
  if (s.status === "open" && before.status === "pending_agency") {
    if (before.claimedBy) {
      await notify([before.claimedBy], {
        title: "Request declined by your agency",
        body: `${before.hospitalName || "The hospital"} request on ${when(s)} was not approved.`,
        data,
      });
    }
    return;
  }

  if (s.status === "claimed" && (before.status === "open" || before.status === "pending_agency")) {
    if (isVisit(s)) {
      await notify([s.posterId], {
        title: "Doctor confirmed ✅",
        body: `${doctor}${s.claimedAgencyName ? ` (${s.claimedAgencyName})` : ""} is coming for ${s.serviceName || "your visit"} on ${when(s)}. Reaches by ${reachBy(s)}.`,
        data,
      });
    } else if (posterUid(s)) {
      await notify([posterUid(s)], {
        title: "Shift filled",
        body: `${doctor} claimed ${s.hospitalName || "the"} shift on ${when(s)}.`,
        data,
      });
    }
    if (!isVisit(s) && s.claimedAgencyId && s.claimedAgencyId !== posterUid(s)) {
      await notify([s.claimedAgencyId], {
        title: "Your doctor claimed a shift",
        body: `${doctor} · ${s.hospitalName || ""} · ${s.area || ""} · ${when(s)}. Reach by ${reachBy(s)}.`,
        data,
      });
    }
    return;
  }

  if (s.status === "on_duty") {
    const late = Number(s.lateMinutes || 0);
    if (isVisit(s)) {
      await notify([s.posterId], { title: "Doctor has arrived", body: `${doctor} has reached you.`, data });
    }
    if (late > 0 && agency) {
      await notify([agency], {
        title: "Doctor checked in late",
        body: `${doctor} checked in ${late} min late for ${isVisit(s) ? s.serviceName || "a home visit" : s.hospitalName || "a shift"}.`,
        data,
      });
    }
    return;
  }

  if (s.status === "completed" && isVisit(s)) {
    await notify([s.posterId], {
      title: "Visit completed",
      body: `${doctor} has completed your ${s.serviceName || "home visit"}.`,
      data,
    });
    return;
  }

  if (s.status === "absent") {
    const text = `${doctor} did not check in for ${isVisit(s) ? s.serviceName || "the home visit" : s.hospitalName || "the shift"} on ${when(s)}.`;
    await notify([isVisit(s) ? s.posterId : posterUid(s), agency], { title: "Doctor no-show", body: text, data });
    return;
  }

  if (s.status === "cancelled" && s.claimedBy) {
    await notify([s.claimedBy], {
      title: "Shift cancelled",
      body: `${isVisit(s) ? s.serviceName || "The home visit" : `${s.hospitalName || "The"} shift`} on ${when(s)} was cancelled.`,
      data,
    });
  }
}

// ----------------------------------------------------------------- triggers

exports.notifyCareShift = onDocumentWritten("shifts/{id}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return;
  const ref = event.data.after.ref;

  if (!before) {
    if (after.status !== "open" || after.teamId) return; // team members are picked, not offered
    await offer(ref, await enforceDutyRate(ref, after));
    return;
  }
  if (before.status !== after.status) await onStatusChange(ref.id, before, after);
});

/**
 * Every 5 minutes: offer home visits to everyone once the agency window
 * ends, and remind doctors an hour before their shift or visit.
 */
const NO_SHOW_AFTER_MS = 4 * 60 * 60000; // as the app: 4 h after the start

/** Changes a shift's status only if it is still [from] (no double marking). */
async function moveStatus(ref, from, ok, update, extra) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== from || !ok(snap.data())) return false;
    tx.update(ref, update);
    if (extra) extra(tx, snap.data());
    return true;
  });
}

/**
 * A hospital's team request: agency care physicians are told at once; when a
 * doctor accepts, his agency is told so it can pick the team.
 */
exports.notifyTeamRequest = onDocumentWritten("team_requests/{id}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return;
  const id = event.params.id;
  const data = { type: "care_shift", shiftId: id };

  if (!before) {
    if (after.status !== "open") return;
    await enforceDutyRate(event.data.after.ref, after);
    const snap = await db.collection("care_physicians").get();
    const uids = [];
    snap.forEach((d) => {
      const p = d.data();
      if (fits(after, p)) uids.push(d.id);
    });
    await notify(uids, {
      title: "👥 Team needed",
      body: `${after.hospitalName || "A hospital"} needs ${after.teamSize || "several"} care physicians · ${when(after)}. Accept to be considered.`,
      data,
    });
    return;
  }

  // the team was placed: the applicants who were not picked are told
  if (before.status === "open" && after.status === "filled") {
    const picked = new Set(list(after.allocatedUids));
    const others = list(after.applicantUids).filter((u) => !picked.has(u));
    await notify(others, {
      title: "Full-time job: not selected",
      body: `${after.hospitalName || "The hospital"} placed other care physicians for its full-time team. Keep an eye on new openings.`,
      data,
    });
    return;
  }

  const had = list(before.applicantUids).length;
  const now = list(after.applicantUids).length;
  // enough applicants to choose from (3), and a full shortlist (10): tell the care agencies
  const crossed = [3, 10].find((n) => had < n && now >= n);
  if (crossed) {
    const agencies = await db.collection("agencies").where("agencyType", "==", "care_physician").get();
    const ids = agencies.docs.filter((d) => d.data().active !== false).map((d) => d.id);
    await notify(ids, {
      title: crossed === 10 ? "Full shortlist ready" : "Applicants for a full-time team",
      body: crossed === 10
        ? `${after.hospitalName || "A hospital"} has 10 applicants. Place the full-time team of ${after.teamSize || 3}.`
        : `${now} care physicians applied to ${after.hospitalName || "a hospital"}'s full-time team. You can place the team now.`,
      data,
    });
  }
});

const DUTY_KEY = /^(\d{4}-\d{2}-\d{2})\|(morning|evening|night)$/;
const dutyText = (key) => {
  const m = DUTY_KEY.exec(String(key || ""));
  return m ? `${m[1]} ${m[2]}` : "a duty";
};

/** A duty team was formed: tell the three physicians and the hospital. */
exports.notifyDutyTeam = onDocumentWritten("duty_teams/{id}", async (event) => {
  if (!event.data.after.exists) return;
  if (event.data.before.exists) {
    // a physician is moving to another hospital: tell this team's hospital and agency
    const was = event.data.before.data();
    const now = event.data.after.data();
    const fresh = Object.entries(now.leaving || {}).filter(([uid]) => !(was.leaving || {})[uid]);
    for (const [, l] of fresh) {
      await notify([now.posterId, now.agencyId], {
        title: "A care physician is moving",
        body: `${l.name || "A care physician"} moves to ${l.toHospital || "another hospital"} from ${l.from}. A replacement is needed at ${now.hospitalName || "your hospital"}.`,
        data: { type: "care_shift", shiftId: event.params.id },
      });
    }
    return;
  }
  const t = event.data.after.data();
  const names = list(t.memberNames);
  const data = { type: "care_shift", shiftId: event.params.id };
  await notify(list(t.members), {
    title: "You are on the duty roster",
    body: `${t.hospitalName || "Hospital"} · weekly rotation from ${t.anchor}. Open the app to see your duties.`,
    data,
  });
  if (t.posterId) {
    await notify([t.posterId], {
      title: "Your care physician team is ready",
      body: `${names.join(", ")} (${t.agencyName || "agency"}) will work the weekly rotation from ${t.anchor}.`,
      data,
    });
  }
});

/** Leave and swap requests: offer them, then report the outcome. */
exports.notifyDutyRequest = onDocumentWritten("duty_requests/{id}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return;
  const data = { type: "care_shift", shiftId: event.params.id };
  const who = after.requesterName || "A colleague";

  if (!before) {
    if (after.type === "swap" && after.targetUid) {
      await notify([after.targetUid], {
        title: "Duty swap request",
        body: `${who} asks to swap ${dutyText(after.sourceKey)} for your ${dutyText(after.targetKey)}.`,
        data,
      });
    } else if (after.type === "leave" && after.status === "awaiting_agency") {
      // the doctor's agency approves the leave first (a freelancer's goes to
      // the MyDox admin panel, no push)
      if (after.approverId && after.approverId !== "platform") {
        await notify([after.approverId], {
          title: "Leave request",
          body: `${who} asks for leave on ${dutyText(after.sourceKey)}. Open Leave requests to answer.`,
          data,
        });
      }
    } else if (after.type === "leave") {
      await notify(list(after.poolUids), {
        title: "Cover needed",
        body: `${after.hospitalName || "A hospital"} · ${dutyText(after.sourceKey)}. First to accept takes the duty.`,
        data,
      });
    }
    return;
  }
  if (before.status === after.status) return;

  if (["awaiting_agency", "awaiting_hospital"].includes(before.status) && after.status === "pending") {
    await notify([after.requesterUid], {
      title: "Leave approved",
      body: `Your leave on ${dutyText(after.sourceKey)} at ${after.hospitalName || "the hospital"} is approved. We are finding a relief physician.`,
      data,
    });
    await notify(list(after.poolUids), {
      title: "Cover needed",
      body: `${after.hospitalName || "A hospital"} · ${dutyText(after.sourceKey)}. First to accept takes the duty.`,
      data,
    });
    return;
  }
  if (["awaiting_agency", "awaiting_hospital"].includes(before.status) && after.status === "declined") {
    await notify([after.requesterUid], {
      title: "Leave not approved",
      body: `Your leave on ${dutyText(after.sourceKey)} at ${after.hospitalName || "the hospital"} was not approved. Your duty is unchanged.`,
      data,
    });
    return;
  }

  if (after.status === "accepted") {
    const taker = after.acceptedByName || "A colleague";
    await notify([after.requesterUid], {
      title: after.type === "swap" ? "Swap accepted" : "Your leave is covered",
      body: after.type === "swap"
        ? `${taker} accepted the swap for ${dutyText(after.sourceKey)}.`
        : `${taker} will cover ${dutyText(after.sourceKey)}.`,
      data,
    });
    const team = await db.collection("duty_teams").doc(String(after.teamId)).get();
    const poster = team.exists ? team.data().posterId : null;
    if (poster) {
      await notify([poster], {
        title: "Duty change confirmed",
        body: after.type === "swap"
          ? `${who} and ${taker} swapped duties on ${dutyText(after.sourceKey)}.`
          : `${taker} now covers ${dutyText(after.sourceKey)} for ${who}.`,
        data,
      });
    }
  } else if (after.status === "declined") {
    await notify([after.requesterUid], {
      title: "Swap declined",
      body: `${after.targetName || "Your teammate"} declined the swap for ${dutyText(after.sourceKey)}. Your duty is unchanged.`,
      data,
    });
  }
});

exports.careShiftSweep = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Asia/Kolkata", timeoutSeconds: 120 },
  async () => {
    const now = Date.now();
    const stamp = new Date(now).toISOString();

    const open = await db.collection("shifts").where("status", "==", "open").get();
    for (const d of open.docs) {
      const s = d.data();
      // start time passed and nobody accepted: no longer "finding a doctor"
      if (startMs(s) <= now) {
        try {
          const moved = await moveStatus(d.ref, "open", (x) => startMs(x) <= now,
            { status: "unfilled", unfilledAt: stamp });
          if (moved && posterUid(s)) {
            await notify([posterUid(s)], isVisit(s) ? {
              title: "No doctor was available",
              body: `Sorry, no care physician could take your ${s.serviceName || "home visit"} on ${when(s)}. Please book again.`,
              data: { type: "care_shift", shiftId: d.id },
            } : {
              title: "Shift not filled",
              body: `No care physician claimed your ${s.hospitalName ? s.hospitalName + " " : ""}shift on ${when(s)}, so it was closed. Please post it again.`,
              data: { type: "care_shift", shiftId: d.id },
            });
          }
        } catch (e) {
          console.error("unfilled failed", d.id, e);
        }
        continue;
      }
      if ((list(s.offerAgencyIds).length === 0 && s.agencyFirst !== true) || agencyWindowOpen(s, now) || s.openToAllPushed) continue;
      try {
        await offer(d.ref, s);
        await d.ref.update({ openToAllPushed: true });
      } catch (e) {
        console.error("open-to-all push failed", d.id, e);
      }
    }

    // team requests that started without a full team
    const teams = await db.collection("team_requests").where("status", "==", "open").get();
    for (const d of teams.docs) {
      const t = d.data();
      if (closesMs(t) > now) continue;
      try {
        await moveStatus(d.ref, "open", (x) => closesMs(x) <= now,
          { status: "unfilled", unfilledAt: stamp });
        if (posterUid(t)) {
          await notify([posterUid(t)], {
            title: "Team not filled",
            body: `${list(t.allocatedUids).length} of ${t.teamSize} care physicians were allocated for ${when(t)}.`,
            data: { type: "care_shift", shiftId: d.id },
          });
        }
      } catch (e) {
        console.error("team unfilled failed", d.id, e);
      }
    }

    const claimed = await db.collection("shifts").where("status", "==", "claimed").get();
    for (const d of claimed.docs) {
      const s = d.data();
      const start = startMs(s);
      // never checked in: a no-show, whether or not the doctor opens the app
      // (the status change sends the no-show pushes)
      if (!s.checkInAt && now > start + NO_SHOW_AFTER_MS) {
        try {
          await moveStatus(d.ref, "claimed", (x) => !x.checkInAt,
            { status: "absent", absentAt: stamp, absentBy: "server" },
            () => {});
        } catch (e) {
          console.error("no-show failed", d.id, e);
        }
        continue;
      }
      if (s.reminderSent || !s.claimedBy || !(start > now) || start - now > 60 * 60000) continue;
      try {
        await notify([s.claimedBy], {
          title: isVisit(s) ? "Home visit in 1 hour" : "Shift starts in 1 hour",
          body: `${isVisit(s) ? `${s.serviceName || "Home visit"} · ${s.address || s.area || ""}` : s.hospitalName || ""}. Please reach by ${reachBy(s)} and check in.`,
          data: { type: "care_shift", shiftId: d.id },
        });
        await d.ref.update({ reminderSent: true });
      } catch (e) {
        console.error("reminder failed", d.id, e);
      }
    }
  }
);

exports.notifyJobInterest = onDocumentCreated("jobs/{jobId}/interests/{uid}", async (event) => {
  const i = event.data && event.data.data();
  if (!i) return;
  const job = (await db.collection("jobs").doc(event.params.jobId).get()).data();
  if (!job || !posterUid(job)) return;
  await notify([posterUid(job)], {
    title: "New interest in your job",
    body: `${i.name || "A care physician"} (${i.qualification || "doctor"}${i.experienceYears ? `, ${i.experienceYears} yrs` : ""}) is interested in ${job.title || "your job"}.`,
    data: { type: "care_job", jobId: event.params.jobId },
  });
});

// for tests
exports._test = { servesArea, fits, parseLocal, startMs, reachBy, agencyWindowOpen };

