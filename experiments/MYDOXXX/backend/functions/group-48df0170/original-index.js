const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * When a caller creates calls/{callId} (status "ringing"), push a high-priority
 * data message to every device of the callee so the phone rings even when the
 * app is closed. The app's background handler turns it into a full-screen
 * "Incoming video call" notification.
 */
exports.notifyIncomingCall = onDocumentCreated("calls/{callId}", async (event) => {
  const call = event.data && event.data.data();
  if (!call || call.status !== "ringing" || !call.calleeUid) return;

  const userRef = admin.firestore().collection("users").doc(call.calleeUid);
  const user = await userRef.get();
  const tokens = (user.data() && user.data().fcmTokens) || [];
  if (tokens.length === 0) return;

  const title = call.audioOnly ? "Incoming audio call" : "Incoming video call";
  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    data: {
      type: "incoming_call",
      audioOnly: call.audioOnly ? "true" : "false",
      callId: event.params.callId,
      callerName: String(call.callerName || "Someone"),
      callerUid: String(call.callerUid || ""),
    },
    android: { priority: "high", ttl: 45 * 1000 },
    apns: {
      headers: { "apns-priority": "10", "apns-push-type": "alert", "apns-expiration": String(Math.floor(Date.now() / 1000) + 45) },
      payload: {
        aps: {
          alert: {
            title,
            body: `${call.callerName || "Someone"} is calling you…`,
          },
          sound: "default",
          "content-available": 1,
          "interruption-level": "time-sensitive",
        },
      },
    },
  });

  // Drop tokens that are no longer valid.
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      dead.push(tokens[i]);
    }
  });
  if (dead.length) {
    await userRef.update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead),
    });
  }
});

// Push notifications for request popups (hospital / doctor / ambulance / patient)
const notifications = require("./notifications");
exports.notifyAppointment = notifications.notifyAppointment;
exports.widenRequestSearch = notifications.widenRequestSearch;
exports.notifyChatMessage = notifications.notifyChatMessage;

// Push notifications for care physician shifts, home visits and jobs
const carePhysician = require("./care_physician");
exports.notifyCareShift = carePhysician.notifyCareShift;
exports.careShiftSweep = carePhysician.careShiftSweep;
exports.notifyJobInterest = carePhysician.notifyJobInterest;
exports.notifyTeamRequest = carePhysician.notifyTeamRequest;
exports.notifyDutyTeam = carePhysician.notifyDutyTeam;
exports.notifyDutyRequest = carePhysician.notifyDutyRequest;

const nurseStaffing = require("./nurse_staffing");
exports.notifyNurseShift = nurseStaffing.notifyNurseShift;
exports.nurseShiftSweep = nurseStaffing.nurseShiftSweep;
exports.notifyNurseJobInterest = nurseStaffing.notifyNurseJobInterest;
exports.notifyNurseTeamRequest = nurseStaffing.notifyNurseTeamRequest;
exports.notifyNurseDutyTeam = nurseStaffing.notifyNurseDutyTeam;
exports.notifyNurseDutyRequest = nurseStaffing.notifyNurseDutyRequest;

// Push notifications for technician shifts, jobs and partner (agency) duties
const technicianStaffing = require("./technician_staffing");
exports.notifyTechnicianShift = technicianStaffing.notifyTechnicianShift;
exports.technicianShiftSweep = technicianStaffing.technicianShiftSweep;
exports.notifyTechnicianJobInterest = technicianStaffing.notifyTechnicianJobInterest;
exports.notifyTechnicianTeamRequest = technicianStaffing.notifyTechnicianTeamRequest;
exports.notifyTechnicianDutyTeam = technicianStaffing.notifyTechnicianDutyTeam;
exports.notifyTechnicianDutyRequest = technicianStaffing.notifyTechnicianDutyRequest;
