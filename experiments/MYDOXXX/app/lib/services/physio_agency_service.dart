import 'dart:math' show Random;

import 'app_database.dart';
import '../config/experiment_environment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/safe_cast.dart';

import 'auth_service.dart';
import 'firestore_service.dart';
import '../utils/ist_timestamp.dart';
import '../utils/ist_clock.dart';

/// Physio agencies partnered with the app (added by the admin) and the
/// agency-first routing of physio requests:
///
///   * A physio request that goes out to everyone (no physio picked, or the
///     picked physio declined / was offline) first goes to the on-duty
///     physios of a partner agency that serves the patient's area
///     (routingStage 'team') for the agency's accept time (default 15 min).
///     "Agency 1" comes first: see [compareAgencyOrder].
///   * If none of them accepts in time (or all of them decline) it opens to
///     every physio in the area (routingStage 'freelance').
///   * No active partner agency in the area (or nobody of theirs on duty):
///     it goes straight to the freelance physios.
///
/// First to accept wins (FirestoreService.acceptProviderRequest).
class PhysioAgencyService {
  static final _db = AppDatabase.instance;

  static const String collection = 'agencies';
  static const int defaultAcceptWindowMin = 15;
  static const double defaultCommissionPct = 20;

  // Routing stages (same strings as the handover document)
  static const String stageTeam = 'team';
  static const String stageFreelance = 'freelance';

  static DateTime? _dt(dynamic raw) => istTimeOf(raw);

  /// "07:45 PM" for a stored time, or '' if missing.
  static String timeLabel(dynamic raw) {
    final d = _dt(raw);
    if (d == null) return '';
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  static List<String> areasOf(Map<String, dynamic> agency) =>
      (agency['areas'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();

  static int acceptWindowOf(Map<String, dynamic> agency) =>
      (toNum(agency['acceptWindowMin'])?.toInt() ?? defaultAcceptWindowMin)
          .clamp(1, 60);

  // ------------------------------------------------------------ pure rules

  /// True when the physio is on duty for [agencyId] and can take its jobs.
  static bool isOnAgencyDuty(Map<String, dynamic> physio, String agencyId) =>
      agencyId.isNotEmpty &&
      physio['agencyId'] == agencyId &&
      physio['workMode'] == 'agency' &&
      physio['isOnline'] != false &&
      physio['isVerified'] == true &&
      !FirestoreService.isProviderBlocked(physio);

  /// Whether a physio is free at [time] given their schedule for that date
  /// (doctor_schedules/{uid}/dates/{yyyy-MM-dd}, null = not set) and the
  /// time slots already booked for them that day.
  static bool isSlotFree({
    required String time,
    Map<String, dynamic>? schedule,
    Iterable<String> bookedSlots = const [],
  }) {
    String norm(String t) =>
        (FirestoreService.normalizeTimeSlot(t) ?? t).trim().toUpperCase();
    final slot = norm(time);
    if (slot.isEmpty) return true;
    if (bookedSlots.map(norm).contains(slot)) return false;
    if (schedule == null) return true;
    if (schedule['isAvailable'] == false) return false;
    final slots = (schedule['timeSlots'] as List<dynamic>? ?? const [])
        .map((e) => norm(e.toString()))
        .toList();
    return slots.isEmpty || slots.contains(slot);
  }

  /// The order agencies are offered a request in, "Agency 1" first: an
  /// agency's optional `priority` number (lower = first); then the oldest
  /// agency (`createdAt`); then name, then id, so the order never depends on
  /// the order the list was read in.
  static int compareAgencyOrder(
      Map<String, dynamic> a, Map<String, dynamic> b) {
    num priority(Map<String, dynamic> x) =>
        toNum(x['priority']) ?? double.infinity;
    final byPriority = priority(a).compareTo(priority(b));
    if (byPriority != 0) return byPriority;
    final never = DateTime(9999);
    final byAge = (istTimeOf(a['createdAt']) ?? never)
        .compareTo(istTimeOf(b['createdAt']) ?? never);
    if (byAge != 0) return byAge;
    final byName = (a['name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['name'] ?? '').toString().toLowerCase());
    if (byName != 0) return byName;
    return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
  }

  /// Where a request for [location] goes first. [agencies] and [physios]
  /// are documents with their id under 'id' / 'uid'. Only on-duty physios
  /// free in the booked time slot ([available] uids; null = not checked)
  /// get it. Agencies are tried in [compareAgencyOrder] ("Agency 1" first):
  /// the first active agency serving the area that has someone free holds the
  /// request; an agency with nobody free does not hold it. If none has,
  /// it goes straight to every physio in the area (freelancers).
  static Map<String, dynamic> routeFor({
    required String location,
    required List<Map<String, dynamic>> agencies,
    required List<Map<String, dynamic>> physios,
    Set<String>? available,
    DateTime? now,
  }) {
    Map<String, dynamic>? best;
    var bestTeam = <String>[];
    final ordered = [...agencies]..sort(compareAgencyOrder);
    for (final agency in ordered) {
      if (agency['active'] != true) continue;
      if (!FirestoreService.providerServesArea(areasOf(agency), location)) {
        continue;
      }
      final id = (agency['id'] ?? '').toString();
      final team = [
        for (final p in physios)
          if (isOnAgencyDuty(p, id) &&
              (available == null || available.contains(p['uid'])))
            p['uid'].toString()
      ];
      if (team.isNotEmpty) {
        best = agency;
        bestTeam = team;
        break; // the first agency in line with someone free takes it
      }
    }
    final at = now ?? IstClock.now();
    if (best == null) {
      return {'routingStage': stageFreelance, 'agencyId': null};
    }
    return {
      'routingStage': stageTeam,
      'agencyId': best['id'],
      'agencyName': best['name'],
      // The agency's physios who get Accept / Decline (free in the slot)
      'agencyOfferedTo': bestTeam,
      'agencyOfferedAt': at.toIso8601String(),
      'agencyOfferExpiresAt':
          at.add(Duration(minutes: acceptWindowOf(best))).toIso8601String(),
    };
  }

  /// True while only the agency's on-duty physios may take the request.
  static bool isAgencyWindowOpen(Map<String, dynamic> request,
      {DateTime? now}) {
    if (request['routingStage'] != stageTeam) return false;
    final expires = _dt(request['agencyOfferExpiresAt']);
    return expires != null && (now ?? IstClock.now()).isBefore(expires);
  }

  /// Whether a broadcast physio request is offered to [physio] ([uid])
  /// right now: during the agency window only the agency's on-duty physios
  /// who were free in the time slot, everyone in the area after.
  static bool isOfferedTo(
      Map<String, dynamic> request, Map<String, dynamic> physio,
      {String? uid, DateTime? now}) {
    if (isAgencyWindowOpen(request, now: now)) {
      if (!isOnAgencyDuty(physio, (request['agencyId'] ?? '').toString())) {
        return false;
      }
      final offeredTo = request['agencyOfferedTo'];
      if (offeredTo is! List) return true; // routed before slot checks
      return offeredTo.contains(uid ?? physio['uid']);
    }
    return true;
  }

  // ------------------------------------------------------------- routing

  static Future<List<Map<String, dynamic>>> _activeAgencies() async {
    final snap =
        await _db.collection(collection).where('active', isEqualTo: true).get();
    return [
      for (final d in snap.docs)
        // care physician agencies place doctors; they get no physio requests
        if (d.data()['agencyType'] != 'care_physician' && d.data()['agencyType'] != 'nurse' && d.data()['agencyType'] != 'technician') {...d.data(), 'id': d.id}
    ];
  }

  static Future<List<Map<String, dynamic>>> _agencyPhysios(
      Iterable<String> agencyIds) async {
    final ids = agencyIds.where((e) => e.isNotEmpty).toSet().toList();
    final out = <Map<String, dynamic>>[];
    // whereIn takes up to 30 values per query
    for (var i = 0; i < ids.length; i += 30) {
      final snap = await _db
          .collection('therapists')
          .where('agencyId',
              whereIn:
                  ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30))
          .get();
      out.addAll([
        for (final d in snap.docs) {...d.data(), 'uid': d.id}
      ]);
    }
    return out;
  }

  /// Routing fields for a physio request in [location] on [date] (dd/MM/yyyy)
  /// at [time] that is about to go out to everyone. Falls back to freelance
  /// if the lookup fails.
  static Future<Map<String, dynamic>> routingFor(String location,
      {String date = '', String time = ''}) async {
    try {
      final agencies = await _activeAgencies();
      final serving = agencies
          .where(
              (a) => FirestoreService.providerServesArea(areasOf(a), location))
          .toList();
      if (serving.isEmpty) {
        return routeFor(
            location: location, agencies: const [], physios: const []);
      }
      final physios =
          await _agencyPhysios(serving.map((a) => a['id'].toString()));
      final onDuty = physios
          .where((p) => serving.any(
              (a) => isOnAgencyDuty(p, a['id'].toString())))
          .toList();
      final free = await Future.wait(
          onDuty.map((p) => _isFreeAt(p['uid'].toString(), date, time)));
      final available = {
        for (var i = 0; i < onDuty.length; i++)
          if (free[i]) onDuty[i]['uid'].toString()
      };
      return routeFor(
          location: location,
          agencies: serving,
          physios: physios,
          available: available);
    } catch (_) {
      return {'routingStage': stageFreelance, 'agencyId': null};
    }
  }

  /// Physio free on [date] at [time]: their schedule allows the slot and
  /// they have no other booking then.
  static Future<bool> _isFreeAt(String uid, String date, String time) async {
    if (date.trim().isEmpty || time.trim().isEmpty) return true;
    final results = await Future.wait([
      FirestoreService.getDoctorDateSchedule(
          doctorUid: uid, dateKey: FirestoreService.normalizeDateKey(date)),
      FirestoreService.getDoctorBookedTimeSlots(doctorUid: uid, date: date),
    ]);
    return isSlotFree(
      time: time,
      schedule: results[0] as Map<String, dynamic>?,
      bookedSlots: results[1] as List<String>,
    );
  }

  /// Opens agency-stage requests to all physios once the agency's accept
  /// time has run out, or as soon as every on-duty team physio declined.
  /// Runs from the physio dashboards and patient screens every minute.
  static Future<int> escalateExpired() async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('routingStage', isEqualTo: stageTeam)
          .get();
      final teams = <String, List<Map<String, dynamic>>>{};
      var opened = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status'] != 'Broadcasted') continue;
        var escalate = !isAgencyWindowOpen(data);
        if (!escalate) {
          final agencyId = (data['agencyId'] ?? '').toString();
          final offeredTo = data['agencyOfferedTo'];
          final team = offeredTo is List
              ? offeredTo.map((e) => e.toString()).toList()
              : (teams[agencyId] ??= (await _agencyPhysios([agencyId]))
                      .where((p) => isOnAgencyDuty(p, agencyId))
                      .toList())
                  .map((p) => p['uid'].toString())
                  .toList();
          final declined = (data['declinedBy'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toSet();
          // every physio it was offered to declined: open it now
          escalate = team.every(declined.contains);
        }
        if (escalate && await _openToFreelance(doc.reference)) opened++;
      }
      return opened;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> _openToFreelance(
          DocumentReference<Map<String, dynamic>> ref) =>
      _db.runTransaction<bool>((tx) async {
        final data = (await tx.get(ref)).data();
        if (data == null ||
            data['routingStage'] != stageTeam ||
            data['status'] != 'Broadcasted') {
          return false;
        }
        tx.update(ref, {
          'routingStage': stageFreelance,
          'agencyId': null,
          'escalatedFromAgencyId': data['agencyId'],
          'escalatedAt': IstClock.now().toIso8601String(),
        });
        return true;
      });

  // -------------------------------------------------------------- admin

  static Stream<List<Map<String, dynamic>>> agenciesStream() =>
      _db.collection(collection).snapshots().map((s) => [
            for (final d in s.docs)
              // care physician agencies (doctor duties) are not physio agencies
              if (d.data()['agencyType'] != 'care_physician' && d.data()['agencyType'] != 'nurse' && d.data()['agencyType'] != 'technician')
                {...d.data(), 'id': d.id}
          ]..sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase())));

  /// Every agency, both types (admin list).
  static Stream<List<Map<String, dynamic>>> allAgenciesStream() =>
      _db.collection(collection).snapshots().map((s) => [
            for (final d in s.docs) {...d.data(), 'id': d.id}
          ]..sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase())));

  /// Admin deletes an agency. Its physios stay on the app as freelancers
  /// (profile, ratings and history kept); a care physician agency's doctors,
  /// hospitals and duties lists are deleted with it. The agency can no
  /// longer log in.
  static Future<void> deleteAgency(String id) async {
    final physios = await _db
        .collection('therapists')
        .where('agencyId', isEqualTo: id)
        .get();
    final writes = <void Function(WriteBatch)>[
      for (final d in physios.docs)
        (b) => b.update(d.reference, {
              'agencyId': FieldValue.delete(),
              'agencyName': FieldValue.delete(),
              'organisation': FieldValue.delete(),
              'agencyCommissionPercent': FieldValue.delete(),
              'workMode':
                  d.data()['workMode'] == 'offline' ? 'offline' : 'freelance',
            }),
    ];
    final members =
        await _db.collection(collection).doc(id).collection('members').get();
    for (final d in members.docs) {
      writes.add((b) => b.delete(d.reference));
    }
    for (final col in ['agency_doctors', 'agency_hospitals', 'duties']) {
      final snap =
          await _db.collection(col).where('agencyId', isEqualTo: id).get();
      for (final d in snap.docs) {
        writes.add((b) => b.delete(d.reference));
      }
    }
    writes.add((b) => b.delete(_db.collection(collection).doc(id)));
    // a batch holds at most 500 writes
    for (var i = 0; i < writes.length; i += 400) {
      final batch = _db.batch();
      for (final w in writes.skip(i).take(400)) {
        w(batch);
      }
      await batch.commit();
    }
  }

  /// Admin pauses / resumes an agency (a paused agency gets no requests).
  static Future<void> setAgencyActive(String id, bool active) => _db
      .collection(collection)
      .doc(id)
      .set({'active': active, 'updatedAt': IstClock.now().toIso8601String()},
          SetOptions(merge: true));

  /// Last 10 digits of a mobile number: how agencies are matched at login.
  static String phoneKey(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  /// Physios currently in [agencyId] (for the admin's team view).
  static Stream<List<Map<String, dynamic>>> teamStream(String agencyId) => _db
      .collection('therapists')
      .where('agencyId', isEqualTo: agencyId)
      .snapshots()
      .map((s) => [
            for (final d in s.docs) {...d.data(), 'uid': d.id}
          ]);

  /// Create (id == null) or update an agency. A rename or new commission is
  /// copied onto the agency's physios.
  ///
  /// The agency logs in with [email] and a password it chooses itself: when
  /// the agency has no login yet one is created for the email and a
  /// "choose your password" email is sent to it. [phone] is only contact
  /// information.
  static Future<void> saveAgency({
    String? id,
    required String name,
    required String phone,
    required String email,
    required String agencyType,
    required List<String> areas,
    required double commissionPct,
    required int acceptWindowMin,
    required bool active,
  }) async {
    final now = IstClock.now().toIso8601String();
    final key = phoneKey(phone);
    final mail = email.trim().toLowerCase();
    final sameMail =
        await _db.collection(collection).where('email', isEqualTo: mail).get();
    if (sameMail.docs.any((d) => d.id != id)) {
      throw Exception('Another agency already uses the email $mail.');
    }
    // the agency's own login (created once, for this email)
    var ownerUid = '';
    if (id != null) {
      final old = (await _db.collection(collection).doc(id).get()).data();
      if ((old?['email'] ?? '').toString().toLowerCase() == mail) {
        ownerUid = (old?['ownerUid'] ?? '').toString();
      }
    }
    if (ownerUid.isEmpty) ownerUid = await createAgencyLogin(mail);
    final data = {
      'email': mail,
      'ownerUid': ownerUid,
      'role': 'agency',
      'name': name,
      'organisation': name,
      'phone': key,
      'mobileNumber': key,
      'phoneKey': key,
      'agencyType': agencyType,
      'areas': areas,
      // first area, for screens that show one place
      'city': areas.isEmpty ? '' : areas.first,
      'commissionPct': commissionPct,
      'acceptWindowMin': acceptWindowMin,
      'active': active,
      'isVerified': true,
      'updatedAt': now,
    };
    if (id == null) {
      await _db.collection(collection).add({
        ...data,
        'createdAt': now,
        'createdBy': 'admin',
        // Care physician agency: money split of each duty (changeable later
        // in the Control Room settings, from the agency agreement)
        if (agencyType == 'care_physician' || agencyType == 'nurse' || agencyType == 'technician') ...{
          'splitDoctorPct': 80,
          'splitAgencyPct': 15,
          'splitAppPct': 5,
        },
      });
      return;
    }
    await _db.collection(collection).doc(id).set(data, SetOptions(merge: true));
    if (agencyType == 'care_physician' || agencyType == 'nurse' || agencyType == 'technician') return;
    final team = await _db
        .collection('therapists')
        .where('agencyId', isEqualTo: id)
        .get();
    final batch = _db.batch();
    for (final d in team.docs) {
      batch.update(d.reference, {
        'organisation': name,
        'agencyName': name,
        'agencyCommissionPercent': commissionPct,
      });
    }
    await batch.commit();
  }

  /// Creates the Firebase login for an agency's [email] (without signing the
  /// admin out: a second app instance does it) and emails the agency a link to
  /// choose its own password. Returns the new login's uid.
  static Future<String> createAgencyLogin(String email) async {
    // The shared lab must not create live accounts or email real recipients.
    // Run this before creating a secondary Firebase app or touching Auth.
    ExperimentEnvironment.requireExternalActions();
    FirebaseApp app;
    try {
      app = Firebase.app('agency-login');
    } catch (_) {
      app = await Firebase.initializeApp(
          name: 'agency-login', options: Firebase.app().options);
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    final rnd = Random.secure();
    const chars =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final temp = List.generate(24, (_) => chars[rnd.nextInt(chars.length)]).join();
    try {
      final cred =
          await auth.createUserWithEmailAndPassword(email: email, password: temp);
      // the link opens the app's own page and is valid for 15 minutes
      await AuthService.sendResetLink(email, auth: auth);
      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception(
            'The email $email already has an account. Use a different email for the agency.');
      }
      throw Exception(e.message ?? 'Could not create the agency login.');
    } finally {
      try {
        await auth.signOut();
      } catch (_) {}
    }
  }

  /// Admin removes a physio from an agency: they stay on the app as a
  /// freelancer with their profile, ratings and history.
  static Future<void> removeFromAgency(String physioUid) =>
      leaveAgency(physioUid, reason: 'removed by admin');

  // -------------------------------------------------------------- physio

  /// Physio joins a partner agency (one agency at a time).
  static Future<void> joinAgency(
      String physioUid, Map<String, dynamic> agency) async {
    final ref = _db.collection('therapists').doc(physioUid);
    final now = IstClock.now().toIso8601String();
    final current = (await ref.get()).data() ?? {};
    final previous = (current['agencyId'] ?? '').toString();
    final agencyId = agency['id'].toString();
    if (previous == agencyId) return;
    final batch = _db.batch();
    if (previous.isNotEmpty) {
      batch.set(
          _db
              .collection(collection)
              .doc(previous)
              .collection('members')
              .doc(physioUid),
          {
            'status': 'left',
            'leftAt': now,
            'leftReason': 'joined another agency'
          },
          SetOptions(merge: true));
    }
    batch.set(
        _db
            .collection(collection)
            .doc(agencyId)
            .collection('members')
            .doc(physioUid),
        {'status': 'active', 'joinedAt': now, 'name': current['name'] ?? ''},
        SetOptions(merge: true));
    batch.update(ref, {
      'agencyId': agencyId,
      'agencyName': agency['name'],
      'organisation': agency['name'],
      'agencyCommissionPercent':
          toNum(agency['commissionPct'])?.toDouble() ?? defaultCommissionPct,
      if (current['workMode'] != 'offline') 'workMode': 'agency',
    });
    await batch.commit();
  }

  /// Physio leaves (or is removed from) their agency and becomes freelance.
  /// Visits, ratings and the membership history are kept.
  static Future<void> leaveAgency(String physioUid,
      {String reason = 'left'}) async {
    final ref = _db.collection('therapists').doc(physioUid);
    final current = (await ref.get()).data() ?? {};
    final agencyId = (current['agencyId'] ?? '').toString();
    final batch = _db.batch();
    if (agencyId.isNotEmpty) {
      batch.set(
          _db
              .collection(collection)
              .doc(agencyId)
              .collection('members')
              .doc(physioUid),
          {
            'status': 'left',
            'leftAt': IstClock.now().toIso8601String(),
            'leftReason': reason,
          },
          SetOptions(merge: true));
    }
    batch.update(ref, {
      'agencyId': FieldValue.delete(),
      'agencyName': FieldValue.delete(),
      'organisation': FieldValue.delete(),
      'agencyCommissionPercent': FieldValue.delete(),
      'workMode': current['workMode'] == 'offline' ? 'offline' : 'freelance',
    });
    await batch.commit();
  }
}

