import 'service_otp.dart';
import 'app_database.dart';
import 'dart:math';
import '../utils/safe_cast.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'firestore_service.dart';
import '../utils/ist_timestamp.dart';
import '../utils/ist_clock.dart';

/// Emergency Help (SOS) pipeline:
///   1. hospitals within 4 km of the patient   -> first to accept is assigned
///   2. doctors near the assigned hospital      -> preferred doctors first,
///      then 4 km -> 6 km -> 8 km (a step every minute)
///   3. ambulances near the PATIENT's live location -> 4 km -> 6 km -> 8 km
/// The whole process must finish within [lifetime], otherwise the request is
/// closed and deleted.
class SosService {
  static final _db = AppDatabase.instance;

  static const String type = 'SOS Emergency Pipeline';
  static const Duration lifetime = Duration(minutes: 5);
  static const int stepSeconds = 60; // radius grows every minute
  static const int preferredWindowSeconds = 60; // preferred doctors go first

  static DateTime? _dt(dynamic raw) => istTimeOf(raw);

  static double _km(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000.0;

  /// Distance in km between two coordinates.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) =>
      _km(lat1, lng1, lat2, lng2);

  static double _radiusAfter(DateTime? start, {int offsetSeconds = 0}) {
    if (start == null) return 4;
    final s = IstClock.now().difference(start).inSeconds - offsetSeconds;
    return (4 + 2 * (max(0, s) ~/ stepSeconds)).clamp(4, 8).toDouble();
  }

  static DateTime expiry(Map<String, dynamic> sos) =>
      _dt(sos['sosExpiresAt']) ??
      (_dt(sos['createdAt']) ?? IstClock.now()).add(lifetime);

  /// Time a doctor / ambulance has to be there once they accept, by how far
  /// they are (doctor: from the assigned hospital; ambulance: from the
  /// patient): <=4 km 15 min, <=6 km 25 min,
  /// <=8 km 30 min.
  static int etaMinutesForKm(double km) => km <= 4 ? 15 : (km <= 6 ? 25 : 30);

  static String _otp() => ServiceOtp.generate();

  /// One OTP per SOS request. The same code is used for the ambulance
  /// (pickup) and for the hospital (arrival).
  static String newOtp() => _otp();

  /// Doctor stage: preferred doctors only for the first minute (if the
  /// hospital has any), then the radius widens 4 -> 6 -> 8 km.
  static ({bool preferredOnly, double radius}) doctorPhase(
      Map<String, dynamic> sos) {
    final start = _dt(sos['doctorStageStartedAt']);
    final hasPreferred =
        ((sos['preferredDoctorUids'] as List?) ?? const []).isNotEmpty;
    if (start == null) return (preferredOnly: hasPreferred, radius: 4);
    final elapsed = IstClock.now().difference(start).inSeconds;
    if (hasPreferred && elapsed < preferredWindowSeconds) {
      return (preferredOnly: true, radius: 4);
    }
    return (
      preferredOnly: false,
      radius: _radiusAfter(start, offsetSeconds: hasPreferred ? preferredWindowSeconds : 0),
    );
  }

  /// Hospital stage radius: hospitals within 4 km first, 6 km after a minute
  /// and 8 km after two minutes (counted from the request).
  static double hospitalRadius(Map<String, dynamic> sos) =>
      _radiusAfter(_dt(sos['createdAt']));

  /// Ambulance stage radius: 4 -> 6 -> 8 km, a step every minute.
  static double ambulanceRadius(Map<String, dynamic> sos) =>
      _radiusAfter(_dt(sos['ambulanceStageStartedAt']));

  // ---------------------------------------------------------------- lookups

  /// Verified doctors of [category] with their LIVE location (saved by the
  /// doctor app) within 12 km of the assigned hospital: uid -> km. The wider
  /// 12 km pool lets doctors who move closer later still be asked; who is
  /// actually asked follows the 4 -> 6 -> 8 km steps with live distances.
  static Future<Map<String, double>> doctorCandidates({
    required String category,
    required double hospitalLat,
    required double hospitalLng,
  }) async {
    final docs = await _db.collection('doctors').get();
    final out = <String, double>{};
    for (final d in docs.docs) {
      final data = d.data();
      if (data['isVerified'] != true || FirestoreService.isProviderBlocked(data)) {
        continue;
      }
      if (data['isOnline'] == false) continue; // offline: no emergency calls
      if (!FirestoreService.isDoctorSpecialtyMatching(
          (data['category'] ?? '').toString(), category)) {
        continue;
      }
      final lat = toNum(data['latitude'])?.toDouble();
      final lng = toNum(data['longitude'])?.toDouble();
      if (lat == null || lng == null) continue; // no live location saved yet
      final km = _km(hospitalLat, hospitalLng, lat, lng);
      if (km <= 12) out[d.id] = km;
    }
    return out;
  }

  /// Verified ambulances (live location saved) within 12 km of the PATIENT's
  /// live location that are not already on a dispatch: uid -> km. Pickup of
  /// the patient is what matters, so ambulances are measured from the patient;
  /// who is asked follows the 4 -> 6 -> 8 km steps with live distances.
  static Future<Map<String, double>> ambulanceCandidates({
    required double patientLat,
    required double patientLng,
  }) async {
    final busy = await FirestoreService.getBusyAmbulanceUids();
    final snap = await _db.collection('ambulances').get();
    final out = <String, double>{};
    for (final a in snap.docs) {
      final d = a.data();
      if (d['isVerified'] != true || busy.contains(a.id)) continue;
      final lat = toNum(d['latitude'])?.toDouble();
      final lng = toNum(d['longitude'])?.toDouble();
      if (lat == null || lng == null) continue;
      final km = _km(patientLat, patientLng, lat, lng);
      if (km <= 12) out[a.id] = km;
    }
    return out;
  }

  // ----------------------------------------------------------- transitions

  /// First hospital to accept gets the request. Works out which doctors
  /// (preferred ones first) will be asked next. Returns false if the request
  /// was already taken / declined / expired.
  static Future<bool> acceptHospital({
    required String appointmentId,
    required String hospitalUid,
    required String hospitalName,
    required double hospitalLat,
    required double hospitalLng,
    required List<String> preferredDoctorUids,
  }) async {
    final ref = _db.collection('appointments').doc(appointmentId);
    final first = (await ref.get()).data();
    if (first == null) return false;
    final category =
        (first['emergencyCategory'] ?? first['doctorCategory'] ?? 'General Physician')
            .toString();

    final candidates = await doctorCandidates(
        category: category, hospitalLat: hospitalLat, hospitalLng: hospitalLng);
    // Preferred doctors are always within 4 km of the hospital.
    final preferred = preferredDoctorUids
        .where((u) => (candidates[u] ?? 99) <= 4)
        .toList();

    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return false;
      if (data['status'] != 'Pending Hospital Acceptance') return false;
      if (FirestoreService.isUrgentRequestExpired(data)) return false;
      final declined = (data['declinedHospitalUids'] as List?) ?? const [];
      if (declined.contains(hospitalUid)) return false;
      tx.update(ref, {
        'status': 'Pending Doctor Assignment',
        'assignedHospitalName': hospitalName,
        'assignedHospitalUid': hospitalUid,
        'assignedHospitalLat': hospitalLat,
        'assignedHospitalLng': hospitalLng,
        'hospitalAcceptedAt': IstClock.now().toIso8601String(),
        'sosDoctorCandidatesKm': candidates,
        'preferredDoctorUids': preferred,
        'doctorStageStartedAt': IstClock.now().toIso8601String(),
      });
      return true;
    });
  }

  /// A hospital declining only removes the request for that hospital.
  static Future<void> declineHospital(String appointmentId, String hospitalUid) =>
      _db.collection('appointments').doc(appointmentId).update({
        'declinedHospitalUids': FieldValue.arrayUnion([hospitalUid]),
      });

  /// First ambulance to accept gets the dispatch.
  static Future<bool> acceptAmbulance({
    required String appointmentId,
    required String ambulanceUid,
    required String driverName,
    required String vehicleNumber,
    double? distanceKm,
  }) async {
    // An ambulance already on a dispatch can't take another until the
    // patient has been handed over to the hospital.
    if ((await FirestoreService.getBusyAmbulanceUids()).contains(ambulanceUid)) {
      return false;
    }
    final ref = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return false;
      if (data['status'] != 'Pending Ambulance Dispatch') return false;
      if (FirestoreService.isUrgentRequestExpired(data)) return false;
      final declined = (data['declinedAmbulanceUids'] as List?) ?? const [];
      if (declined.contains(ambulanceUid)) return false;
      final km = distanceKm ??
          ((data['sosAmbulanceCandidatesKm'] as Map?)?[ambulanceUid] as num?)
              ?.toDouble() ??
          4;
      final eta = etaMinutesForKm(km);
      final now = IstClock.now();
      tx.update(ref, {
        'status': 'Ambulance Dispatched',
        'ambulanceDistanceKm': km,
        'ambulanceEtaMinutes': eta,
        'ambulanceDeadlineAt': now.add(Duration(minutes: eta)).toIso8601String(),
        'assignedAmbulanceDriver': driverName,
        'assignedVehicleNumber': vehicleNumber,
        'assignedAmbulanceUid': ambulanceUid,
        'ambulanceDispatchedAt': IstClock.now().toIso8601String(),
      });
      return true;
    });
  }

  static Future<void> declineAmbulance(String appointmentId, String ambulanceUid) =>
      _db.collection('appointments').doc(appointmentId).update({
        'declinedAmbulanceUids': FieldValue.arrayUnion([ambulanceUid]),
      });

  // ------------------------------------------------- OTPs, pickup and drop

  static int _minutesBetween(DateTime a, DateTime b) =>
      (b.difference(a).inSeconds / 60).ceil().clamp(0, 100000);

  /// Ambulance OTP: the patient is picked up. Records the pickup time
  /// (dispatch -> pickup) and whether the ambulance was within its limit.
  static Future<bool> verifyAmbulancePickup({
    required String appointmentId,
    required String enteredOtp,
    required String ambulanceUid,
  }) {
    final ref = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null) return false;
      if (data['status'] != 'Ambulance Dispatched' ||
          data['assignedAmbulanceUid'] != ambulanceUid) {
        return false;
      }
      final otp = (data['ambulanceOtp'] ?? data['otp'] ?? '').toString();
      if (otp.trim() != enteredOtp.trim()) return false;

      final now = IstClock.now();
      final dispatched = _dt(data['ambulanceDispatchedAt']) ?? now;
      final deadline = _dt(data['ambulanceDeadlineAt']);
      tx.update(ref, {
        'status': 'Patient Picked Up',
        'ambulancePickedUpAt': now.toIso8601String(),
        'ambulancePickupMinutes': _minutesBetween(dispatched, now),
        if (deadline != null) 'ambulanceLate': now.isAfter(deadline),
        if (deadline != null && now.isAfter(deadline))
          'ambulanceLateByMinutes': _minutesBetween(deadline, now),
      });
      return true;
    });
  }

  /// Hospital OTP: the patient has reached the hospital. Records the drop
  /// time (pickup -> hospital), frees the ambulance (the case is no longer
  /// an ambulance dispatch) and starts the hospital consultation.
  static Future<bool> verifyHospitalArrival({
    required String appointmentId,
    required String enteredOtp,
    required String hospitalUid,
  }) {
    final ref = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null) return false;
      if (data['assignedHospitalUid'] != hospitalUid) return false;
      final status = (data['status'] ?? '').toString();
      // after ambulance pickup, or directly when the patient drives himself
      final ok = status == 'Patient Picked Up' ||
          (status == 'Confirmed' && data['requiresAmbulance'] == false);
      if (!ok) return false;
      if ((data['hospitalOtp'] ?? data['otp'] ?? '').toString().trim() !=
          enteredOtp.trim()) {
        return false;
      }

      final now = IstClock.now();
      final picked = _dt(data['ambulancePickedUpAt']);
      final dispatched = _dt(data['ambulanceDispatchedAt']);
      final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
      tx.update(ref, {
        'status': 'In Progress',
        'hospitalReachedAt': now.toIso8601String(),
        'startedAt': now.toIso8601String(),
        'startTimeFormatted':
            '${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}',
        if (picked != null) 'ambulanceDropMinutes': _minutesBetween(picked, now),
        if (dispatched != null)
          'ambulanceTripMinutes': _minutesBetween(dispatched, now),
      });
      return true;
    });
  }

  /// Hospital enters the doctor's arrival OTP: records the doctor's arrival
  /// and whether it was within the 15 / 25 / 30 minute limit.
  static Future<bool> verifyDoctorArrival({
    required String appointmentId,
    required String enteredOtp,
    required String hospitalUid,
  }) {
    final ref = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null) return false;
      if (data['assignedHospitalUid'] != hospitalUid) return false;
      if (data['doctorReachedAt'] != null) return false;
      if ((data['doctorOtp'] ?? '').toString().trim() != enteredOtp.trim()) {
        return false;
      }
      final now = IstClock.now();
      final deadline = _dt(data['doctorDeadlineAt']);
      tx.update(ref, {
        'doctorReachedAt': now.toIso8601String(),
        if (deadline != null) 'doctorLate': now.isAfter(deadline),
        if (deadline != null && now.isAfter(deadline))
          'doctorLateByMinutes': _minutesBetween(deadline, now),
      });
      return true;
    });
  }

  /// Statuses in which the assigned doctor can close the emergency.
  static const Set<String> _doctorCanClose = {
    'Pending Ambulance Dispatch',
    'Ambulance Dispatched',
    'Patient Picked Up',
    'Confirmed',
    'In Progress',
  };

  /// True while the assigned doctor can take the patient's OTP.
  static bool doctorCanClose(Map<String, dynamic> sos) =>
      _doctorCanClose.contains((sos['status'] ?? '').toString());

  /// Doctor enters the patient's emergency OTP when they meet: the
  /// emergency is closed (Completed) and the ambulance is freed.
  static Future<bool> closeWithPatientOtp({
    required String appointmentId,
    required String enteredOtp,
    required String doctorUid,
  }) {
    final ref = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null || data['consultationType'] != type) return false;
      if (data['doctorUid'] != doctorUid || !doctorCanClose(data)) return false;
      final otp = (data['otp'] ?? data['hospitalOtp'] ?? '').toString().trim();
      if (otp.isEmpty || otp != enteredOtp.trim()) return false;
      final now = IstClock.now();
      tx.update(ref, {
        'status': 'Completed',
        'completedAt': now.toIso8601String(),
        'endTimeFormatted': _hm(now),
        'doctorPatientOtpAt': now.toIso8601String(),
        if (data['startedAt'] == null) 'startedAt': now.toIso8601String(),
      });
      return true;
    });
  }

  static String _hm(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Human-readable timing lines for a SOS case (shown on the ambulance,
  /// hospital and patient screens).
  static List<String> timingLines(Map<String, dynamic> sos) {
    final out = <String>[];
    final now = IstClock.now();

    final dDeadline = _dt(sos['doctorDeadlineAt']);
    if (dDeadline != null) {
      final eta = sos['doctorEtaMinutes'];
      if (sos['doctorReachedAt'] != null) {
        final late = sos['doctorLate'] == true;
        out.add(late
            ? 'Doctor reached hospital ${sos['doctorLateByMinutes']} min late (limit $eta min)'
            : 'Doctor reached hospital on time (limit $eta min)');
      } else {
        final left = dDeadline.difference(now).inMinutes;
        out.add(left >= 0
            ? 'Doctor must reach hospital by ${_hm(dDeadline)} ($eta min limit, $left min left)'
            : 'Doctor is ${-left} min late (was due ${_hm(dDeadline)})');
      }
    }

    final aDeadline = _dt(sos['ambulanceDeadlineAt']);
    if (aDeadline != null) {
      final eta = sos['ambulanceEtaMinutes'];
      if (sos['ambulancePickedUpAt'] != null) {
        final late = sos['ambulanceLate'] == true;
        out.add(
            'Pickup time: ${sos['ambulancePickupMinutes']} min${late ? ' (late by ${sos['ambulanceLateByMinutes']} min, limit $eta)' : ' (within $eta min limit)'}');
      } else {
        final left = aDeadline.difference(now).inMinutes;
        out.add(left >= 0
            ? 'Ambulance must reach patient by ${_hm(aDeadline)} ($eta min limit, $left min left)'
            : 'Ambulance is ${-left} min late (was due ${_hm(aDeadline)})');
      }
    }
    if (sos['ambulanceDropMinutes'] != null) {
      out.add(
          'Drop time: ${sos['ambulanceDropMinutes']} min (patient pickup to hospital)');
    }
    if (sos['ambulanceTripMinutes'] != null) {
      out.add('Total ambulance trip: ${sos['ambulanceTripMinutes']} min');
    }
    return out;
  }
}
