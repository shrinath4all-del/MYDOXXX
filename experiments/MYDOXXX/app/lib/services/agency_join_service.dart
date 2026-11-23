import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/ist_clock.dart';
import 'app_database.dart';
import 'care_physician_service.dart';
import 'nurse_staffing_service.dart';
import 'technician_staffing_service.dart';

/// A freelancer (care physician, nurse or technician) asks to join an agency;
/// the agency sees who it is (name, experience, qualification, registration
/// number…) and approves or rejects. Only after approval is the freelancer
/// the agency's member, and only a member can apply for full-time jobs
/// (locum shifts and home visits stay open to freelancers).
///
/// The request is the agency's member record (`agency_doctors`, also used for
/// nurses and technicians) with `status`:
///   'pending'   waiting for the agency (`active: false`)
///   'approved'  a member (`active: true`, as before this existed)
///   'rejected'  the agency said no
/// Records without a status were added before approvals existed: members.
///
/// On the freelancer's profile: `joinAgencyId`, `joinAgencyName`,
/// `joinStatus` ('pending' / 'rejected') while there is no approval yet.
class AgencyJoinService {
  AgencyJoinService._();

  static FirebaseFirestore get _db => AppDatabase.instance;
  static const String col = 'agency_doctors';

  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  /// The profile collection of each role.
  static const Map<String, String> roleLabels = {
    CarePhysicianService.collection: 'Care physician',
    NurseStaffingService.collection: 'Nurse',
    TechnicianStaffingService.collection: 'Technician',
  };

  static String _str(Object? v) => (v ?? '').toString();

  /// Whether [me] is an approved agency member (may apply for full-time jobs).
  static bool isMember(Map<String, dynamic> me) =>
      _str(me['agencyId']).isNotEmpty;

  /// The agency [me] is waiting for, or ''.
  static String pendingAgencyName(Map<String, dynamic> me) =>
      _str(me['joinStatus']) == pending ? _str(me['joinAgencyName']) : '';

  /// The agency that turned [me] down most recently, or ''.
  static String rejectedBy(Map<String, dynamic> me) =>
      _str(me['joinStatus']) == rejected ? _str(me['joinAgencyName']) : '';

  /// Why [me] cannot apply for a full-time job yet, or null.
  static String? fullTimeBlockReason(Map<String, dynamic> me) {
    if (isMember(me)) return null;
    final waiting = pendingAgencyName(me);
    if (waiting.isNotEmpty) {
      return 'Your request to join $waiting is waiting for the agency. '
          'You can apply for full-time jobs once it approves you.';
    }
    return 'Full-time jobs are filled through agencies. Join an agency first; '
        'once it approves you, you can apply.';
  }

  /// The details the agency sees in a request (and keeps for its members).
  static Map<String, dynamic> details(
      Map<String, dynamic> me, String profileCollection) {
    final years = me['experienceYears'] ?? me['experience'];
    return {
      'name': _str(me['name']),
      'phone': _str(me['phone'] ?? me['mobileNumber']),
      'email': _str(me['email']),
      'qualification': _str(me['qualification']),
      'regNo': _str(me['regNo'] ?? me['registrationNumber']),
      'experienceYears': years is num ? years.round() : int.tryParse(_str(years)) ?? 0,
      'areas': [for (final a in (me['areas'] as List? ?? const [])) a.toString()],
      'dutyTypes': [
        for (final a in (me['dutyTypes'] as List? ?? const [])) a.toString()
      ],
      'isVerified': me['isVerified'] == true,
      'profileCollection': profileCollection,
      'role': roleLabels[profileCollection] ?? 'Member',
    };
  }

  /// The freelancer asks [agencyId] to take them on.
  static Future<void> request(Map<String, dynamic> me, String profileCollection,
      String agencyId, String agencyName) async {
    final uid = _str(me['uid']);
    if (uid.isEmpty || agencyId.isEmpty) {
      throw Exception('Pick an agency to join.');
    }
    if (_str(me['agencyId']) == agencyId) {
      throw Exception('You are already a member of $agencyName.');
    }
    // the saved profile has the details the agency should see
    try {
      final saved = (await _db.collection(profileCollection).doc(uid).get()).data();
      if (saved != null) me = {...me, ...saved, 'uid': uid};
    } catch (_) {}
    final now = IstClock.now().toIso8601String();
    final batch = _db.batch();
    // a request to another agency that was still waiting is withdrawn
    final before = _str(me['joinAgencyId']);
    if (before.isNotEmpty && before != agencyId && _str(me['joinStatus']) == pending) {
      batch.set(_db.collection(col).doc('${before}_$uid'),
          {'status': 'withdrawn', 'active': false, 'withdrawnAt': now},
          SetOptions(merge: true));
    }
    batch.set(_db.collection(col).doc('${agencyId}_$uid'), {
      ...details(me, profileCollection),
      'agencyId': agencyId,
      'agencyName': agencyName,
      'userUid': uid,
      'placementType': 'pool',
      'joinedBy': 'request',
      'status': pending,
      'active': false,
      'requestedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
    batch.set(_db.collection(profileCollection).doc(uid), {
      'joinAgencyId': agencyId,
      'joinAgencyName': agencyName,
      'joinStatus': pending,
      'joinRequestedAt': now,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Requests waiting for [agencyId], newest first.
  static Stream<List<Map<String, dynamic>>> pendingStream(String agencyId) => _db
      .collection(col)
      .where('agencyId', isEqualTo: agencyId)
      .where('status', isEqualTo: pending)
      .snapshots()
      .map((s) => [for (final d in s.docs) {...d.data(), 'id': d.id}]
        ..sort((a, b) =>
            _str(b['requestedAt']).compareTo(_str(a['requestedAt']))));

  /// The agency takes the freelancer on: they become its member.
  static Future<void> approve(Map<String, dynamic> rec) async {
    final uid = _str(rec['userUid']);
    final agencyId = _str(rec['agencyId']);
    final agencyName = _str(rec['agencyName']);
    final profileCol = _str(rec['profileCollection']);
    final profile = (await _db.collection(profileCol).doc(uid).get()).data();
    if (profile == null) {
      throw Exception('This account no longer exists.');
    }
    final me = {...profile, 'uid': uid};
    switch (profileCol) {
      case NurseStaffingService.collection:
        await NurseStaffingService.joinAgency(me, agencyId, agencyName);
      case TechnicianStaffingService.collection:
        await TechnicianStaffingService.joinAgency(me, agencyId, agencyName);
      default:
        await CarePhysicianService.joinAgency(me, agencyId, agencyName);
    }
    final now = IstClock.now().toIso8601String();
    final batch = _db.batch();
    batch.set(_db.collection(col).doc(_str(rec['id'])),
        {'status': approved, 'active': true, 'approvedAt': now},
        SetOptions(merge: true));
    batch.set(_db.collection(profileCol).doc(uid), {
      'joinStatus': FieldValue.delete(),
      'joinAgencyId': FieldValue.delete(),
      'joinAgencyName': FieldValue.delete(),
      'joinRequestedAt': FieldValue.delete(),
    }, SetOptions(merge: true));
    await batch.commit();
    await _tell(uid, 'Welcome to $agencyName',
        '$agencyName approved your request. You can now apply for full-time jobs.');
  }

  /// The agency turns the freelancer down (they stay a freelancer).
  static Future<void> reject(Map<String, dynamic> rec) async {
    final uid = _str(rec['userUid']);
    final agencyName = _str(rec['agencyName']);
    final profileCol = _str(rec['profileCollection']);
    final now = IstClock.now().toIso8601String();
    final batch = _db.batch();
    batch.set(_db.collection(col).doc(_str(rec['id'])),
        {'status': rejected, 'active': false, 'rejectedAt': now},
        SetOptions(merge: true));
    if (profileCol.isNotEmpty && uid.isNotEmpty) {
      batch.set(_db.collection(profileCol).doc(uid),
          {'joinStatus': rejected, 'joinRejectedAt': now},
          SetOptions(merge: true));
    }
    await batch.commit();
    await _tell(uid, 'Request not approved',
        '$agencyName did not approve your request. You can ask another agency to take you on.');
  }

  /// A note in the person's notification bell (best effort).
  static Future<void> _tell(String uid, String title, String body) async {
    if (uid.isEmpty) return;
    try {
      await _db.collection('users').doc(uid).collection('notifications').add({
        'type': 'agency_join',
        'title': title,
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
