import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/ist_clock.dart';
import 'agency_join_service.dart';
import 'app_database.dart';
import 'care_physician_service.dart';
import 'nurse_staffing_service.dart';
import 'physio_agency_service.dart';

/// Staff who can join an agency by invite or by request.
enum InviteRole { nurse, carePhysician, therapist }

/// Agency invite links and join requests for nurses, care physicians and
/// physiotherapists.
///
///   * Each agency has an invite code ("SAI-7K3Q") and a link carrying it
///     (`...?invite=SAI-7K3Q`). Whoever signs up with the code, or enters it
///     later in their profile, joins that agency at once as its staff.
///   * Choosing an agency from the list (no code) only sends a join request;
///     the person stays a freelancer until the agency approves it. For care
///     physicians and nurses that request is the IT team's AgencyJoinService
///     (its own "Join requests" screen); the request functions here are used
///     for physiotherapists, which that service does not cover.
///   * The agency can switch its code off or make a new one (the old one then
///     stops working). Either side can end the link later (Leave / Remove).
///
/// Stored on existing records only: `agencies/{id}` keeps `inviteCode`,
/// `inviteKey` (the code without the dash, for look-ups) and `inviteActive`;
/// the staff profile keeps `agencyRequest` while a request is waiting, and
/// `agencyJoinedBy` ('invite' / 'approved') after joining.
class AgencyInviteService {
  AgencyInviteService._();

  static final FirebaseFirestore _db = AppDatabase.instance;

  /// Letters and digits that cannot be mixed up when read aloud or typed
  /// (no 0/O, 1/I/L).
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int randomLength = 4;

  /// The code a sign-up link carried (`?invite=...`), kept until sign-up.
  static String? pendingFromLink;

  // ---------------------------------------------------------------- pure rules

  static InviteRole? roleFromKey(String role) => switch (role) {
        'nurse' => InviteRole.nurse,
        'care_physician' => InviteRole.carePhysician,
        'therapist' => InviteRole.therapist,
        _ => null,
      };

  /// Where this role's profiles are stored.
  static String collectionOf(InviteRole role) => switch (role) {
        InviteRole.nurse => NurseStaffingService.collection,
        InviteRole.carePhysician => CarePhysicianService.collection,
        InviteRole.therapist => 'therapists',
      };

  static String staffWord(InviteRole role) => switch (role) {
        InviteRole.nurse => 'nurses',
        InviteRole.carePhysician => 'care physicians',
        InviteRole.therapist => 'physiotherapists',
      };

  /// Whether [agency] takes this kind of staff.
  static bool agencyServes(Map<String, dynamic> agency, InviteRole role) {
    final type = (agency['agencyType'] ?? '').toString();
    return switch (role) {
      InviteRole.nurse => type == 'nurse',
      InviteRole.carePhysician => type == 'care_physician',
      // physio agencies are every agency that is not one of the other types
      InviteRole.therapist =>
        !const {'care_physician', 'nurse', 'technician'}.contains(type),
    };
  }

  /// "SAI-7K3Q": up to three letters from the agency name, then four random
  /// characters.
  static String newCode(String agencyName, Random random) {
    final letters = agencyName.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    final prefix = letters.isEmpty
        ? 'AGY'
        : letters.substring(0, min(3, letters.length)).padRight(3, 'X');
    final tail = List.generate(
        randomLength, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return '$prefix-$tail';
  }

  /// A typed or pasted code (any case, spaces, with or without the dash, or a
  /// whole invite link) as the look-up key "SAI7K3Q", or '' if it is no code.
  static String keyOf(String typed) {
    var text = typed.trim();
    final link = Uri.tryParse(text);
    final fromLink = link?.queryParameters['invite'];
    if (fromLink != null && fromLink.isNotEmpty) text = fromLink;
    final key = text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return key.length >= 4 && key.length <= 12 ? key : '';
  }

  /// The invite link for [code], on the page the app runs from ([base]).
  static String linkFor(Uri base, String code) => Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: base.path.isEmpty ? '/' : base.path,
        queryParameters: {'invite': code},
      ).toString();

  /// Why [agency] (found by an invite code) cannot take [role], or null.
  static String? inviteProblem(Map<String, dynamic>? agency, InviteRole role) {
    if (agency == null) {
      return 'This invite code was not found. Check it with your agency.';
    }
    if (agency['active'] == false || agency['inviteActive'] == false) {
      return 'This invite code is switched off. Ask your agency for a new one.';
    }
    if (!agencyServes(agency, role)) {
      return 'This invite code is for a different kind of agency, not for '
          '${staffWord(role)}.';
    }
    return null;
  }

  /// The join request waiting on a profile, or null.
  static Map<String, dynamic>? requestOf(Map<String, dynamic>? profile) {
    final r = profile?['agencyRequest'];
    if (r is! Map || (r['agencyId'] ?? '').toString().isEmpty) return null;
    return Map<String, dynamic>.from(r);
  }

  // ------------------------------------------------------ agency: the code

  /// The agency's code, made (unique) the first time it is asked for.
  static Future<String> ensureCode(String agencyId) async {
    final ref = _db.collection('agencies').doc(agencyId);
    final agency = (await ref.get()).data() ?? {};
    final existing = (agency['inviteCode'] ?? '').toString();
    if (existing.isNotEmpty) return existing;
    return _saveNewCode(ref, (agency['name'] ?? '').toString(), active: true);
  }

  /// A new code; the old one stops working at once.
  static Future<String> regenerate(String agencyId) async {
    final ref = _db.collection('agencies').doc(agencyId);
    final agency = (await ref.get()).data() ?? {};
    return _saveNewCode(ref, (agency['name'] ?? '').toString(),
        active: agency['inviteActive'] != false);
  }

  static Future<void> setActive(String agencyId, bool active) => _db
      .collection('agencies')
      .doc(agencyId)
      .set({'inviteActive': active}, SetOptions(merge: true));

  static Future<String> _saveNewCode(
      DocumentReference<Map<String, dynamic>> ref, String name,
      {required bool active}) async {
    final random = Random.secure();
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = newCode(name, random);
      final key = keyOf(code);
      final taken = await _db
          .collection('agencies')
          .where('inviteKey', isEqualTo: key)
          .limit(1)
          .get();
      if (taken.docs.isNotEmpty) continue;
      await ref.set({
        'inviteCode': code,
        'inviteKey': key,
        'inviteActive': active,
        'inviteUpdatedAt': IstClock.now().toIso8601String(),
      }, SetOptions(merge: true));
      return code;
    }
    throw Exception('Could not make a new invite code. Please try again.');
  }

  // ------------------------------------------------ staff: join by code

  /// The agency a code belongs to (with its id), or null.
  static Future<Map<String, dynamic>?> findByCode(String typed) async {
    final key = keyOf(typed);
    if (key.isEmpty) return null;
    final snap = await _db
        .collection('agencies')
        .where('inviteKey', isEqualTo: key)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return {...snap.docs.first.data(), 'id': snap.docs.first.id};
  }

  /// Joins the agency of [code] at once. [me] is the staff profile with its
  /// 'uid'. Returns the agency name. Throws with a message to show if the
  /// code cannot be used.
  static Future<String> joinWithCode(
      InviteRole role, Map<String, dynamic> me, String code) async {
    final agency = await findByCode(code);
    final problem = inviteProblem(agency, role);
    if (problem != null) throw Exception(problem);
    await _join(role, me, agency!);
    final uid = me['uid'].toString();
    final profile = _db.collection(collectionOf(role)).doc(uid);
    // a request still waiting at another agency (AgencyJoinService) is withdrawn
    if (role != InviteRole.therapist) {
      try {
        final saved = (await profile.get()).data() ?? const {};
        final waitingAt = (saved['joinAgencyId'] ?? '').toString();
        if (waitingAt.isNotEmpty &&
            waitingAt != agency['id'] &&
            saved['joinStatus'] == AgencyJoinService.pending) {
          await _db.collection(AgencyJoinService.col).doc('${waitingAt}_$uid').set({
            'status': 'withdrawn',
            'active': false,
            'withdrawnAt': IstClock.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
      } catch (_) {
        // the join itself is done; the old request can still be rejected
      }
    }
    await profile.set({
      'agencyJoinedBy': 'invite',
      'agencyInviteCode': agency['inviteCode'],
      'agencyRequest': FieldValue.delete(),
      'joinAgencyId': FieldValue.delete(),
      'joinAgencyName': FieldValue.delete(),
      'joinStatus': FieldValue.delete(),
      'joinRequestedAt': FieldValue.delete(),
    }, SetOptions(merge: true));
    return (agency['name'] ?? '').toString();
  }

  static Future<void> _join(InviteRole role, Map<String, dynamic> me,
      Map<String, dynamic> agency) {
    final id = agency['id'].toString();
    final name = (agency['name'] ?? '').toString();
    return switch (role) {
      InviteRole.nurse => NurseStaffingService.joinAgency(me, id, name),
      InviteRole.carePhysician => CarePhysicianService.joinAgency(me, id, name),
      InviteRole.therapist =>
        PhysioAgencyService.joinAgency(me['uid'].toString(), agency),
    };
  }

  // ------------------------------------------- staff: request to join

  /// Picked from the list without a code: a request the agency approves.
  static Future<void> requestJoin(InviteRole role, String uid,
          Map<String, dynamic> agency) =>
      _db.collection(collectionOf(role)).doc(uid).set({
        'agencyRequest': {
          'agencyId': agency['id'].toString(),
          'agencyName': (agency['name'] ?? '').toString(),
          'at': IstClock.now().toIso8601String(),
        },
      }, SetOptions(merge: true));

  static Future<void> cancelRequest(InviteRole role, String uid) => _db
      .collection(collectionOf(role))
      .doc(uid)
      .set({'agencyRequest': FieldValue.delete()}, SetOptions(merge: true));

  // ------------------------------------------- agency: the requests

  /// Staff of [role] waiting for [agencyId] to approve them, oldest first.
  static Stream<List<Map<String, dynamic>>> requestsStream(
          InviteRole role, String agencyId) =>
      _db
          .collection(collectionOf(role))
          .where('agencyRequest.agencyId', isEqualTo: agencyId)
          .snapshots()
          .map((s) => [
                for (final d in s.docs) {...d.data(), 'uid': d.id}
              ]..sort((a, b) => (requestOf(a)?['at'] ?? '')
                  .toString()
                  .compareTo((requestOf(b)?['at'] ?? '').toString())));

  static Future<void> approve(InviteRole role, Map<String, dynamic> staff,
      Map<String, dynamic> agency) async {
    await _join(role, staff, agency);
    await _db.collection(collectionOf(role)).doc(staff['uid'].toString()).set({
      'agencyJoinedBy': 'approved',
      'agencyRequest': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  static Future<void> reject(InviteRole role, String uid) =>
      cancelRequest(role, uid);
}
