import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/ist_clock.dart';
import 'agency_invite_service.dart';
import 'app_database.dart';

/// Whoever handed out a referral link or code: an agency, or one of our own
/// marketing people.
class Referrer {
  static const String agency = 'agency';
  static const String marketing = 'marketing';

  final String type;
  final String id;
  final String name;
  final String code;

  /// False when the agency is closed or the code is switched off.
  final bool active;

  /// The stored record (the agency, or the marketing person).
  final Map<String, dynamic> data;

  const Referrer({
    required this.type,
    required this.id,
    required this.name,
    required this.code,
    required this.active,
    this.data = const {},
  });

  bool get isAgency => type == agency;
}

/// "Who referred this person": one link for care physicians, nurses,
/// technicians and physiotherapists.
///
///   * An agency's link (its invite code) and a marketing person's link are the
///     same kind of link: `...?invite=CODE`.
///   * The first code a person uses, at sign-up or later from their profile, is
///     written on their profile as `referredBy` and in `referrals/{uid}` for
///     the back office. It is written ONCE: later codes, leaving the agency or
///     joining another one never change it.
///   * If the code is an agency's and the agency takes this kind of staff, the
///     person also joins that agency at once. They can leave it later; the
///     referral stays.
///
/// The "written once" rule is kept by this code. Database rules that refuse a
/// second write are a separate, reviewed change.
class ReferralService {
  ReferralService._();

  static final FirebaseFirestore _db = AppDatabase.instance;

  /// One record per referred person, keyed by their uid.
  static const String collection = 'referrals';

  /// Where the code was used.
  static const String atSignUp = 'signup';
  static const String fromProfile = 'profile';

  // ---------------------------------------------------------------- pure rules

  /// The referral written on a profile, or null.
  static Map<String, dynamic>? referralOf(Map<String, dynamic>? profile) {
    final r = profile?['referredBy'];
    if (r is! Map || (r['id'] ?? '').toString().isEmpty) return null;
    return Map<String, dynamic>.from(r);
  }

  /// "Sai Services (agency)" / "Ravi Kumar (BFAST team)".
  static String describe(Map<String, dynamic> referral) {
    final name = (referral['name'] ?? '').toString();
    final who =
        referral['type'] == Referrer.marketing ? 'BFAST team' : 'agency';
    return name.isEmpty ? who : '$name ($who)';
  }

  /// The owner of a code as a [Referrer]. [collection] is where it was found.
  static Referrer referrerFrom(
      String collection, String id, Map<String, dynamic> data) {
    final isAgency = collection == 'agencies';
    return Referrer(
      type: isAgency ? Referrer.agency : Referrer.marketing,
      id: id,
      name: (data['name'] ?? '').toString(),
      code: (data['inviteCode'] ?? '').toString(),
      active: data['active'] != false && data['inviteActive'] != false,
      data: {...data, 'id': id},
    );
  }

  /// Why a code cannot be used at all, or null.
  static String? problem(Referrer? referrer) {
    if (referrer == null) {
      return 'This code was not found. Check it with whoever sent it to you.';
    }
    if (!referrer.active) {
      return 'This code is switched off. Ask for a new one.';
    }
    return null;
  }

  /// What the sign-up form says under the code, for someone signing up as
  /// [role]: (the text, whether it is a problem).
  static ({String text, bool problem}) signUpNote(
      Referrer? referrer, InviteRole role) {
    final bad = problem(referrer);
    if (bad != null) return (text: bad, problem: true);
    final r = referrer!;
    if (!r.isAgency) {
      return (
        text: 'This is kept on your profile so we know who brought you to BFAST.',
        problem: false
      );
    }
    if (AgencyInviteService.agencyServes(r.data, role)) {
      return (
        text: 'You join ${r.name} as soon as your account is created. You can '
            'leave the agency later; who referred you stays on your profile.',
        problem: false
      );
    }
    final takes =
        AgencyInviteService.staffWord(AgencyInviteService.roleOfAgency(r.data));
    return (
      text: '${r.name} is an agency for $takes, so you will not be added to '
          'its staff. It is still kept as who referred you.',
      problem: false
    );
  }

  /// The tag written on the profile.
  static Map<String, dynamic> tagFor(Referrer referrer,
          {required String via, required DateTime at}) =>
      {
        'type': referrer.type,
        'id': referrer.id,
        'name': referrer.name,
        'code': referrer.code,
        'via': via,
        'at': at.toIso8601String(),
      };

  /// What to tell the person after a code was used. [joined]: they were added
  /// to the agency. [recorded]: this code became their referral. [earlier]:
  /// the name already on record when it did not. Throws (with the message to
  /// show) when the code did nothing.
  static String outcome(Referrer referrer, InviteRole role,
      {required bool joined, required bool recorded, String earlier = ''}) {
    if (joined) return 'You joined ${referrer.name}.';
    if (recorded) {
      if (!referrer.isAgency) {
        return '${referrer.name} is noted as the one who referred you.';
      }
      final takes = AgencyInviteService.staffWord(
          AgencyInviteService.roleOfAgency(referrer.data));
      return '${referrer.name} is noted as the one who referred you. It is an '
          'agency for $takes, so you were not added to its staff.';
    }
    if (referrer.isAgency) {
      throw Exception(AgencyInviteService.inviteProblem(referrer.data, role) ??
          'This code cannot be used here.');
    }
    throw Exception(earlier.isEmpty
        ? 'Your referral is already noted and cannot be changed.'
        : 'Your referral is already noted ($earlier) and cannot be changed.');
  }

  /// The referral already on record for a person: on their [profile], or in
  /// the back-office [record] that outlives it. Only when this is null may a
  /// new referral be written.
  static Map<String, dynamic>? existing(
      Map<String, dynamic>? profile, Map<String, dynamic>? record) {
    final onProfile = referralOf(profile);
    if (onProfile != null) return onProfile;
    if (record == null || (record['referrerId'] ?? '').toString().isEmpty) {
      return null;
    }
    return {
      'type': record['referrerType'],
      'id': record['referrerId'],
      'name': record['referrerName'],
      'code': record['code'],
      'via': record['via'],
      'at': record['at'],
    };
  }

  /// The back-office record (`referrals/{uid}`) for a [tag] just written on
  /// the profile of [staff].
  static Map<String, dynamic> recordFor(InviteRole role, String uid,
          Map<String, dynamic> tag, Map<String, dynamic> staff) =>
      {
        'uid': uid,
        'role': AgencyInviteService.roleKey(role),
        'staffName': (staff['name'] ?? '').toString(),
        'phone': (staff['phone'] ?? staff['mobileNumber'] ?? '').toString(),
        'referrerType': tag['type'],
        'referrerId': tag['id'],
        'referrerName': tag['name'],
        'code': tag['code'],
        'via': tag['via'],
        'at': tag['at'],
      };

  // ------------------------------------------------------------- using a code

  /// Whoever owns a typed or pasted code (or whole link), or null.
  static Future<Referrer?> resolve(String typed) async {
    final owner = await AgencyInviteService.ownerOfKey(
        AgencyInviteService.keyOf(typed));
    if (owner == null) return null;
    return referrerFrom(owner.collection, owner.id, owner.data);
  }

  /// Uses [typed] for the staff member [me] (their profile with its 'uid'):
  /// joins the agency at once when the code is an agency's and it takes this
  /// [role], and notes the referral if none is on record yet. Returns the
  /// message to show. Throws with a message when the code cannot be used.
  static Future<String> useCode(
      InviteRole role, Map<String, dynamic> me, String typed,
      {required String via}) async {
    final referrer = await resolve(typed);
    final bad = problem(referrer);
    if (bad != null) throw Exception(bad);
    final r = referrer!;
    final joins = r.isAgency && AgencyInviteService.agencyServes(r.data, role);
    if (joins) await AgencyInviteService.joinFound(role, me, r.data);
    final noted = await recordOnce(role, me, r, via: via);
    return outcome(r, role,
        joined: joins, recorded: noted.recorded, earlier: noted.earlier);
  }

  /// Notes [referrer] as the one who referred [me], unless a referral is
  /// already on record (then nothing changes and `earlier` is its name).
  static Future<({bool recorded, String earlier})> recordOnce(
      InviteRole role, Map<String, dynamic> me, Referrer referrer,
      {required String via}) {
    final uid = me['uid'].toString();
    final profile =
        _db.collection(AgencyInviteService.collectionOf(role)).doc(uid);
    final record = _db.collection(collection).doc(uid);
    return _db.runTransaction((tx) async {
      final saved = (await tx.get(profile)).data() ?? const {};
      final kept = (await tx.get(record)).data();
      final earlier = existing(saved, kept);
      if (earlier != null) {
        if (referralOf(saved) == null) {
          // the back-office record outlives the profile: put the tag back
          tx.set(profile, {'referredBy': earlier}, SetOptions(merge: true));
        }
        return (recorded: false, earlier: (earlier['name'] ?? '').toString());
      }
      final tag = tagFor(referrer, via: via, at: IstClock.now());
      tx.set(profile, {'referredBy': tag}, SetOptions(merge: true));
      tx.set(record, recordFor(role, uid, tag, {...saved, ...me}));
      return (recorded: true, earlier: '');
    });
  }

  // ------------------------------------------------------- the back office

  /// "Care physician · joined at sign-up · 23/11/2026" for one record.
  static String summaryOf(Map<String, dynamic> record) {
    final role = AgencyInviteService.roleFromKey((record['role'] ?? '').toString());
    final at = IstClock.tryParse((record['at'] ?? '').toString());
    return [
      if (role != null) staffTitle(role),
      record['via'] == atSignUp ? 'at sign-up' : 'code entered later',
      if (at != null) '${at.day}/${at.month}/${at.year}',
    ].join(' · ');
  }

  /// "Care physician", "Nurse" ...
  static String staffTitle(InviteRole role) => switch (role) {
        InviteRole.nurse => 'Nurse',
        InviteRole.carePhysician => 'Care physician',
        InviteRole.technician => 'Technician',
        InviteRole.therapist => 'Physiotherapist',
      };

  /// Newest first.
  static List<Map<String, dynamic>> newestFirst(
          Iterable<Map<String, dynamic>> referrals) =>
      referrals.toList()
        ..sort((a, b) =>
            (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString()));

  /// Everyone who was referred, newest first.
  static Stream<List<Map<String, dynamic>>> referralsStream() => _db
      .collection(collection)
      .snapshots()
      .map((s) => newestFirst(s.docs.map((d) => d.data())));

  /// The people [referrerId] (an agency or a marketing person) referred.
  static Stream<List<Map<String, dynamic>>> referralsOfStream(
          String referrerId) =>
      _db
          .collection(collection)
          .where('referrerId', isEqualTo: referrerId)
          .snapshots()
          .map((s) => newestFirst(s.docs.map((d) => d.data())));

  /// Our marketing people, by name.
  static Stream<List<Map<String, dynamic>>> marketersStream() => _db
      .collection(AgencyInviteService.referrersCollection)
      .snapshots()
      .map((s) => [
            for (final d in s.docs) {...d.data(), 'id': d.id}
          ]..sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase())));

  /// Adds a marketing person and gives them their own code. Returns the code.
  static Future<String> addMarketer(String name, String phone) async {
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('Enter the person\'s name.');
    final ref = _db.collection(AgencyInviteService.referrersCollection).doc();
    await ref.set({
      'name': clean,
      'phone': phone.trim(),
      'kind': Referrer.marketing,
      'active': true,
      'createdAt': IstClock.now().toIso8601String(),
    });
    return AgencyInviteService.saveNewCode(ref, clean, active: true);
  }

  /// Switches a marketing person's link on or off. People they already
  /// referred keep the record.
  static Future<void> setMarketerActive(String id, bool active) => _db
      .collection(AgencyInviteService.referrersCollection)
      .doc(id)
      .set({'inviteActive': active}, SetOptions(merge: true));
}
