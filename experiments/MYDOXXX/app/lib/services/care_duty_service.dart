import 'app_database.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/care_duty_roster.dart';
import 'care_physician_service.dart';

/// Duty teams: three care physicians (A, B, C) an agency sent to a hospital
/// on a weekly rotation (see [CareDutyRoster]), with leave and swap requests.
///
///   duty_teams/{id}     hospitalId/Name, posterId, agencyId/Name, area,
///                       anchor ('yyyy-MM-dd' Monday), members [uidA, uidB,
///                       uidC], memberNames, memberUids, pay, overrides
///                       {dutyKey: uid}, overrideNames {dutyKey: name},
///                       status 'active'
///   duty_requests/{id}  teamId, type 'leave' | 'swap', status 'pending' |
///                       'accepted' | 'withdrawn' | 'declined', requester*,
///                       sourceKey, targetKey/targetUid (swap), reason, note,
///                       memberUids (team), poolUids (who may cover a leave)
class CareDutyService {
  CareDutyService._();

  static FirebaseFirestore get _db => AppDatabase.instance;
  static const String teamsCol = 'duty_teams';
  static const String requestsCol = 'duty_requests';

  static const int maxReason = 100;
  static const int maxNote = 500;

  static const Map<String, String> leaveReasons = {
    'sick': 'Sick',
    'family': 'Family emergency',
    'personal': 'Personal leave',
    'other': 'Other',
  };

  // ------------------------------------------------------------------ model

  static CareDutyRoster rosterOf(Map<String, dynamic> team) => CareDutyRoster(
        anchorMonday:
            DutySlot.parseDate((team['anchor'] ?? '').toString()) ?? DateTime.utc(2026, 1, 5),
        members: [
          ...CarePhysicianService.listOf(team['members']),
          '',
          '',
        ].take(3).toList(),
        fixed: fixedShiftOf(team),
        overrides: {
          for (final e in ((team['overrides'] as Map?) ?? const {}).entries)
            e.key.toString(): e.value.toString()
        },
      );

  /// The one shift of a single-shift placement ('morning', 'evening',
  /// 'night'), null for the three-physician rotation.
  static DutyShift? fixedShiftOf(Map<String, dynamic> t) {
    final k = (t['fixedShift'] ?? '').toString();
    for (final s in DutyShift.values) {
      if (s.key == k) return s;
    }
    return null;
  }

  static String nameOf(Map<String, dynamic> team, String uid) {
    final members = CarePhysicianService.listOf(team['members']);
    final i = members.indexOf(uid);
    final names = CarePhysicianService.listOf(team['memberNames']);
    if (i >= 0 && i < names.length) return names[i];
    for (final e in ((team['overrideNames'] as Map?) ?? const {}).entries) {
      if (team['overrides'] is Map && (team['overrides'] as Map)[e.key] == uid) {
        return e.value.toString();
      }
    }
    return 'Relief physician';
  }

  /// The name shown for whoever works [slot] now.
  static String assigneeName(Map<String, dynamic> team, DutySlot slot) {
    final uid = rosterOf(team).assigneeOf(slot);
    final names = (team['overrideNames'] as Map?) ?? const {};
    return names[slot.key]?.toString() ?? nameOf(team, uid);
  }

  // ---------------------------------------------------------------- streams

  static List<Map<String, dynamic>> _withIds(
          QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) {...d.data(), 'id': d.id}];

  /// The active teams a physician is a core member of.
  static Stream<List<Map<String, dynamic>>> teamsOf(String uid) => _db
      .collection(teamsCol)
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map((s) => _withIds(s)..removeWhere((t) => t['status'] != 'active'));

  /// The active duty teams of an agency.
  static Stream<List<Map<String, dynamic>>> teamsOfAgency(String agencyId) => _db
      .collection(teamsCol)
      .where('agencyId', isEqualTo: agencyId)
      .snapshots()
      .map((s) => _withIds(s)..removeWhere((t) => t['status'] != 'active'));

  static Stream<List<Map<String, dynamic>>> _combine(
      Stream<List<Map<String, dynamic>>> a,
      Stream<List<Map<String, dynamic>>> b) {
    late StreamController<List<Map<String, dynamic>>> c;
    List<Map<String, dynamic>>? la, lb;
    final subs = <StreamSubscription<void>>[];
    void emit() {
      if (la != null && lb != null) {
        final seen = <String>{};
        c.add([
          for (final r in [...la!, ...lb!])
            if (seen.add(r['id'].toString())) r
        ]);
      }
    }

    c = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        subs.add(a.listen((v) {
          la = v;
          emit();
        }, onError: c.addError));
        subs.add(b.listen((v) {
          lb = v;
          emit();
        }, onError: c.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return c.stream;
  }

  /// Requests a physician is part of: his team's, and leave cover he may take.
  static Stream<List<Map<String, dynamic>>> requestsFor(String uid) => _combine(
        _db
            .collection(requestsCol)
            .where('memberUids', arrayContains: uid)
            .snapshots()
            .map(_withIds),
        _db
            .collection(requestsCol)
            .where('poolUids', arrayContains: uid)
            .snapshots()
            .map(_withIds),
      ).map((l) => l
        ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}')));

  // ------------------------------------------------------------- team setup

  /// The three shifts of the rotation, in the order of the roster's A, B, C.
  static const List<DutyShift> teamShifts = [
    DutyShift.morning,
    DutyShift.evening,
    DutyShift.night,
  ];

  /// Shifts a physician has already claimed that fall on his new rotation
  /// duties (from the first Monday on): they are released.
  static List<String> clashingShiftIds(CareDutyRoster roster, String uid,
      Iterable<Map<String, dynamic>> shifts) {
    final from = roster.anchorMonday;
    final out = <String>[];
    for (final s in shifts) {
      if (s['status'] != 'claimed' || s['claimedBy'] != uid) continue;
      final a = CarePhysicianService.shiftStart(s)?.toUtc();
      final b = CarePhysicianService.shiftEnd(s)?.toUtc();
      if (a == null || b == null) continue;
      if (a.isBefore(CareDutyClock.istToUtc(from.year, from.month, from.day, 0))) {
        continue; // before the rotation starts
      }
      final ist = CareDutyClock.utcToIst(a);
      final day = DateTime.utc(ist.year, ist.month, ist.day);
      final duties = roster.dutiesOf(uid, day.subtract(const Duration(days: 1)),
          day.add(const Duration(days: 1)));
      if (duties.any((d) => a.isBefore(d.end) && d.start.isBefore(b))) {
        out.add(s['id'].toString());
      }
    }
    return out;
  }

  /// The agency places three applicants at the hospital: [byShift] says who
  /// works the Morning, Evening and Night shift of the first week (the
  /// rotation then moves each of them on weekly). They have to be among the
  /// best 10 applicants. [anchor] is the Monday the rotation starts.
  ///
  /// A placed physician's existing locum shift that falls on one of his new
  /// duties is released and opens again for other care physicians.
  static Future<String> createTeam({
    required Map<String, dynamic> request,
    required String agencyId,
    required String agencyName,
    required Map<DutyShift, String> byShift,
  }) async {
    final fixed = fixedShiftOf(request);
    final shifts = fixed == null ? teamShifts : [fixed];
    final orderedUids = [for (final s in shifts) byShift[s] ?? ''];
    if (orderedUids.any((u) => u.isEmpty) ||
        orderedUids.toSet().length != shifts.length) {
      throw Exception(fixed == null
          ? 'Pick a different care physician for each of the three shifts.'
          : 'Pick the care physician for the ${fixed.label} shift.');
    }
    final anchor = DutySlot.parseDate((request['anchor'] ?? '').toString());
    if (anchor == null) {
      throw Exception('The rotation needs a start date.');
    }
    final applicants = (request['applicants'] as Map?) ?? const {};
    final top = CarePhysicianService.shortlist(request).map((e) => e.uid).toSet();
    final names = <String>[];
    for (final uid in orderedUids) {
      final a = applicants[uid] as Map?;
      if (a == null || !top.contains(uid)) {
        throw Exception('Pick only from the best 10 applicants.');
      }
      // no overlap: he cannot be on two full-time duties at the same time
      // (a physician moving from another hospital is the exception)
      if ((a['currentHospital'] ?? '').toString().isEmpty) {
        final at = requestClash(request, await rosterBusy(uid));
        if (at != null) {
          throw Exception(
              '${a['name']} already works a full-time duty at $at at that time. Pick someone else.');
        }
      }
      names.add((a['name'] ?? '').toString());
    }
    final ref = _db.collection(teamsCol).doc();
    final reqRef =
        _db.collection(CarePhysicianService.teamCol).doc(request['id'].toString());
    await _db.runTransaction((tx) async {
      final fresh = (await tx.get(reqRef)).data();
      if (fresh == null || fresh['status'] != 'open') {
        throw Exception('This team request is closed.');
      }
      tx.set(ref, {
        'hospitalId': request['hospitalId'],
        'hospitalName': request['hospitalName'],
        'posterId': request['posterId'],
        'agencyId': agencyId,
        'agencyName': agencyName,
        'area': request['area'],
        'anchor': DutySlot.dateKey(anchor),
        if (fixed != null) 'fixedShift': fixed.key,
        'members': orderedUids,
        'memberNames': names,
        'memberUids': orderedUids,
        'shiftAssignments': {
          for (var i = 0; i < shifts.length; i++) shifts[i].key: orderedUids[i],
        },
        'pay': request['pay'],
        for (final k in const [
          'doctorPay', 'marginAmount', 'saiShare', 'mydoxShare', 'rateSource', 'payPeriod'
        ])
          if (request[k] != null) k: request[k],
        'overrides': <String, dynamic>{},
        'overrideNames': <String, dynamic>{},
        'status': 'active',
        'requestId': request['id'],
        'createdAt': DateTime.now().toIso8601String(),
      });
      tx.update(reqRef, {
        'status': 'filled',
        'allocatedUids': orderedUids,
        'allocatedNames': names,
        'shiftAssignments': {
          for (var i = 0; i < shifts.length; i++) shifts[i].key: names[i],
        },
        'teamId': ref.id,
        'filledAt': DateTime.now().toIso8601String(),
      });
    });

    // placed full time: he works for the agency now (a freelancer joins it)
    final teamData = (await ref.get()).data() ?? const {};
    final roster = rosterOf({...teamData, 'id': ref.id});
    for (final uid in orderedUids) {
      try {
        final profile =
            (await _db.collection(CarePhysicianService.collection).doc(uid).get()).data();
        if (profile != null && (profile['agencyId'] ?? '').toString().isEmpty) {
          await CarePhysicianService.joinAgency(
              {...profile, 'uid': uid}, agencyId, agencyName);
        }
        // a locum shift on one of his new duty times is released and re-offered
        final claimed = await _db
            .collection(CarePhysicianService.shiftsCol)
            .where('claimedBy', isEqualTo: uid)
            .get();
        final shifts = [for (final d in claimed.docs) {...d.data(), 'id': d.id}];
        for (final id in clashingShiftIds(roster, uid, shifts)) {
          await CarePhysicianService.reopenShift(
              id, uid, 'moved_to_full_time');
        }
      } catch (_) {
        // the team exists either way; the agency can fix a single doctor by hand
      }
    }

    // a physician who was placed at another hospital is moving: his old team
    // is told and keeps the rotation until the agency arranges a replacement
    try {
      for (final uid in orderedUids) {
        final old = await _db
            .collection(teamsCol)
            .where('memberUids', arrayContains: uid)
            .get();
        for (final d in old.docs) {
          if (d.id == ref.id || d.data()['status'] != 'active') continue;
          await d.reference.update({
            'leaving.$uid': {
              'name': nameOf(d.data(), uid),
              'from': DutySlot.dateKey(anchor),
              'toHospital': request['hospitalName'],
            },
            'needsMember': true,
          });
        }
      }
    } catch (_) {}

    // they are placed full time: permanent at this hospital in the agency's list
    try {
      final roster = await _db
          .collection('agency_doctors')
          .where('agencyId', isEqualTo: agencyId)
          .get();
      for (final d in roster.docs) {
        if (orderedUids.contains(d.data()['userUid'])) {
          await d.reference.set({
            'placementType': 'permanent',
            'permanentHospitalId': request['hospitalId'],
            'permanentHospitalName': request['hospitalName'],
            'permanentSince': DutySlot.dateKey(anchor),
          }, SetOptions(merge: true));
        }
      }
    } catch (_) {
      // the team exists either way; the agency can mark the placement by hand
    }
    return ref.id;
  }

  // --------------------------------------------------------------- helpers

  /// Everything else this physician is booked for around now (claimed
  /// locum shifts and his duties in other teams), so a change cannot double
  /// book him.
  static Future<List<BusyInterval>> commitmentsOf(String uid,
      {String? exceptTeamId}) async {
    final out = <BusyInterval>[];
    final shifts = await _db
        .collection(CarePhysicianService.shiftsCol)
        .where('claimedBy', isEqualTo: uid)
        .get();
    for (final d in shifts.docs) {
      final s = d.data();
      if (!const {'claimed', 'on_duty', 'pending_agency'}.contains(s['status'])) {
        continue;
      }
      final a = CarePhysicianService.shiftStart(s);
      final b = CarePhysicianService.shiftEnd(s);
      if (a != null && b != null) out.add(BusyInterval(a.toUtc(), b.toUtc()));
    }
    final teams = await _db
        .collection(teamsCol)
        .where('memberUids', arrayContains: uid)
        .get();
    final now = DateTime.now();
    for (final d in teams.docs) {
      if (d.id == exceptTeamId || d.data()['status'] != 'active') continue;
      final roster = rosterOf(d.data());
      final today = CareDutyClock.today(now);
      for (final s in roster.dutiesOf(
          uid, today.subtract(const Duration(days: 1)), today.add(const Duration(days: 400)))) {
        out.add(BusyInterval(s.start, s.end));
      }
    }
    return out;
  }

  /// Whether a full-time request (one shift every day, or all three shifts)
  /// overlaps [busy] (the physician's existing full-time duties) in its first
  /// four weeks. Returns the hospital he is already on, or null if free.
  static String? requestClash(Map<String, dynamic> request, List<BusyInterval> busy) {
    final anchor = DutySlot.parseDate((request['anchor'] ?? '').toString());
    if (anchor == null || busy.isEmpty) return null;
    final fixed = fixedShiftOf(request);
    final shifts = fixed == null ? teamShifts : [fixed];
    for (var d = 0; d < 28; d++) {
      final day = anchor.add(Duration(days: d));
      for (final s in shifts) {
        final slot = DutySlot(day, s);
        for (final b in busy) {
          if (slot.start.isBefore(b.end) && b.start.isBefore(slot.end)) {
            return b.label.isEmpty ? 'another hospital' : b.label;
          }
        }
      }
    }
    return null;
  }

  /// The duties on the hospital rotation rosters this physician works, from
  /// yesterday to 90 days ahead (a shift cannot be claimed over them).
  static Future<List<BusyInterval>> rosterBusy(String uid) async {
    final teams = await _db
        .collection(teamsCol)
        .where('memberUids', arrayContains: uid)
        .get();
    final today = CareDutyClock.today(DateTime.now());
    final out = <BusyInterval>[];
    for (final d in teams.docs) {
      if (d.data()['status'] != 'active') continue;
      final roster = rosterOf(d.data());
      // a rotation has no end: look a year and more ahead, so no locum shift or
      // home visit can be claimed over a full-time duty
      for (final s in roster.dutiesOf(uid,
          today.subtract(const Duration(days: 1)), today.add(const Duration(days: 400)))) {
        out.add(BusyInterval(s.start, s.end, (d.data()['hospitalName'] ?? '').toString()));
      }
    }
    return out;
  }

  static String _trim(String s, int max) =>
      s.trim().length > max ? s.trim().substring(0, max) : s.trim();

  // --------------------------------------------------------------- requests

  /// A pending leave request: the duty stays with its physician until a
  /// relief physician accepts.
  static Future<void> requestLeave({
    required Map<String, dynamic> team,
    required String requesterUid,
    required String requesterName,
    required DutySlot slot,
    required String reason,
    String note = '',
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('Please give a reason.');
    if (cleanReason.length > maxReason) {
      throw Exception('The reason is too long (max $maxReason characters).');
    }
    if (note.length > maxNote) {
      throw Exception('The note is too long (max $maxNote characters).');
    }
    final roster = rosterOf(team);
    if (!slot.start.isAfter(DateTime.now())) {
      throw Exception('That duty has already started.');
    }
    if (roster.assigneeOf(slot) != requesterUid) {
      throw Exception('That duty is not yours.');
    }
    await _noOtherPending(team['id'].toString(), [slot.key]);
    // the agency's other care physicians can cover
    final agencyId = (team['agencyId'] ?? '').toString();
    final pool = <String>[];
    if (agencyId.isNotEmpty) {
      final snap = await _db
          .collection(CarePhysicianService.collection)
          .where('agencyId', isEqualTo: agencyId)
          .get();
      for (final d in snap.docs) {
        if (!roster.members.contains(d.id) && d.data()['available'] != false) {
          pool.add(d.id);
        }
      }
    }
    // the hospital approves the leave first; only then is cover offered
    await _db.collection(requestsCol).add({
      'teamId': team['id'],
      'type': 'leave',
      'status': 'awaiting_hospital',
      'hospitalPosterId': team['posterId'],
      'hospitalName': team['hospitalName'],
      'agencyId': agencyId,
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'sourceKey': slot.key,
      'reason': _trim(cleanReason, maxReason),
      'note': _trim(note, maxNote),
      'memberUids': CarePhysicianService.listOf(team['memberUids']),
      'poolUids': <String>[],
      'pendingPoolUids': pool,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Leave requests waiting for (or answered by) this hospital.
  static Stream<List<Map<String, dynamic>>> leaveRequestsOfHospital(
          String posterId) =>
      _db
          .collection(requestsCol)
          .where('hospitalPosterId', isEqualTo: posterId)
          .snapshots()
          .map((s) => _withIds(s)
            ..removeWhere((r) => r['type'] != 'leave')
            ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}')));

  /// The hospital answers a leave request. Approved: the leave is granted and
  /// the agency's other physicians are offered the duty. Declined: the duty
  /// stays with its physician.
  static Future<void> hospitalDecideLeave(String requestId,
      {required bool approve}) async {
    final ref = _db.collection(requestsCol).doc(requestId);
    await _db.runTransaction((tx) async {
      final r = (await tx.get(ref)).data();
      if (r == null || r['status'] != 'awaiting_hospital') {
        throw Exception('This leave request is already answered.');
      }
      final now = DateTime.now().toIso8601String();
      if (approve) {
        tx.update(ref, {
          'status': 'pending',
          'poolUids': CarePhysicianService.listOf(r['pendingPoolUids']),
          'hospitalApprovedAt': now,
        });
      } else {
        tx.update(ref, {
          'status': 'declined',
          'hospitalDeclined': true,
          'resolvedAt': now,
        });
      }
    });
  }

  /// A pending swap with a teammate: both duties stay as they are until the
  /// teammate accepts.
  static Future<void> requestSwap({
    required Map<String, dynamic> team,
    required String requesterUid,
    required String requesterName,
    required DutySlot mine,
    required String targetUid,
    required DutySlot theirs,
    String reason = 'Swap',
    String note = '',
  }) async {
    final roster = rosterOf(team);
    final now = DateTime.now();
    await _assertSameAgency(team);
    final check = roster.checkSwap(requesterUid, mine, targetUid, theirs, now,
        othersA: await commitmentsOf(requesterUid, exceptTeamId: team['id'].toString()),
        othersB: await commitmentsOf(targetUid, exceptTeamId: team['id'].toString()));
    if (!check.ok) throw Exception(check.problem);
    await _noOtherPending(team['id'].toString(), [mine.key, theirs.key]);
    await _db.collection(requestsCol).add({
      'teamId': team['id'],
      'type': 'swap',
      'status': 'pending',
      'hospitalName': team['hospitalName'],
      'agencyId': team['agencyId'],
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'sourceKey': mine.key,
      'targetUid': targetUid,
      'targetName': nameOf(team, targetUid),
      'targetKey': theirs.key,
      'reason': _trim(reason, maxReason),
      'note': _trim(note, maxNote),
      'memberUids': CarePhysicianService.listOf(team['memberUids']),
      'poolUids': <String>[],
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Duties can only be swapped when all of the team's care physicians belong
  /// to the same agency.
  static Future<void> _assertSameAgency(Map<String, dynamic> team) async {
    final agencies = <String>{};
    for (final uid in CarePhysicianService.listOf(team['memberUids'])) {
      final p = (await _db
              .collection(CarePhysicianService.collection)
              .doc(uid)
              .get())
          .data();
      agencies.add((p?['agencyId'] ?? '').toString());
    }
    if (agencies.length > 1 || agencies.contains('')) {
      throw Exception(
          'Duties can be swapped only when all the care physicians in the team belong to the same agency.');
    }
  }

  /// A duty can be in only one pending request.
  static Future<void> _noOtherPending(String teamId, List<String> keys) async {
    final snap = await _db
        .collection(requestsCol)
        .where('teamId', isEqualTo: teamId)
        .where('status', whereIn: ['pending', 'awaiting_hospital'])
        .get();
    for (final d in snap.docs) {
      final r = d.data();
      if (keys.contains(r['sourceKey']) || keys.contains(r['targetKey'])) {
        throw Exception('That duty is already in another pending request.');
      }
    }
  }

  static Future<void> withdraw(String requestId, String uid) async {
    final ref = _db.collection(requestsCol).doc(requestId);
    await _db.runTransaction((tx) async {
      final r = (await tx.get(ref)).data();
      if (r == null ||
          (r['status'] != 'pending' && r['status'] != 'awaiting_hospital')) {
        throw Exception('This request is already closed.');
      }
      if (r['requesterUid'] != uid) {
        throw Exception('Only the person who asked can withdraw it.');
      }
      tx.update(ref, {
        'status': 'withdrawn',
        'resolvedAt': DateTime.now().toIso8601String(),
      });
    });
  }

  static Future<void> declineSwap(String requestId, String uid) async {
    final ref = _db.collection(requestsCol).doc(requestId);
    await _db.runTransaction((tx) async {
      final r = (await tx.get(ref)).data();
      if (r == null || r['status'] != 'pending' || r['targetUid'] != uid) {
        throw Exception('This request is already closed.');
      }
      tx.update(ref, {
        'status': 'declined',
        'resolvedAt': DateTime.now().toIso8601String(),
      });
    });
  }

  /// A relief physician takes a duty. The first valid acceptance wins.
  static Future<void> acceptRelief(
      String requestId, String uid, String name) async {
    final reqRef = _db.collection(requestsCol).doc(requestId);
    final first = (await reqRef.get()).data();
    if (first == null) throw Exception('This request no longer exists.');
    final teamId = first['teamId'].toString();
    final others = await commitmentsOf(uid, exceptTeamId: teamId);
    final teamRef = _db.collection(teamsCol).doc(teamId);
    await _db.runTransaction((tx) async {
      final r = (await tx.get(reqRef)).data();
      final team = (await tx.get(teamRef)).data();
      if (r == null ||
          team == null ||
          r['status'] != 'pending' ||
          r['type'] != 'leave') {
        throw Exception('Someone else already took this duty.');
      }
      if (!CarePhysicianService.listOf(r['poolUids']).contains(uid)) {
        throw Exception('This cover request is not open to you.');
      }
      final slot = DutySlot.parse(r['sourceKey'].toString());
      if (slot == null) throw Exception('This request is not valid.');
      final roster = rosterOf(team);
      if (roster.assigneeOf(slot) != r['requesterUid']) {
        throw Exception('The duty has changed. This request is out of date.');
      }
      final check = roster.checkTakeOver(uid, slot, DateTime.now(), others: others);
      if (!check.ok) throw Exception(check.problem);
      tx.update(teamRef, {
        'overrides.${slot.key}': uid,
        'overrideNames.${slot.key}': name,
      });
      tx.update(reqRef, {
        'status': 'accepted',
        'acceptedBy': uid,
        'acceptedByName': name,
        'resolvedAt': DateTime.now().toIso8601String(),
      });
      // the relief physician's time is held like any claimed shift
      tx.set(
          CarePhysicianService.scheduleRef(uid),
          {
            'slots': {
              'duty_${teamId}_${slot.key}': {
                'start': slot.start.toIso8601String(),
                'end': slot.end.toIso8601String(),
                'label': '${team['hospitalName']}, ${slot.shift.label} duty',
              },
            },
          },
          SetOptions(merge: true));
    });
  }

  /// The teammate accepts a swap: both duties change together.
  static Future<void> acceptSwap(String requestId, String uid) async {
    final reqRef = _db.collection(requestsCol).doc(requestId);
    final first = (await reqRef.get()).data();
    if (first == null) throw Exception('This request no longer exists.');
    final teamId = first['teamId'].toString();
    final othersA = await commitmentsOf(first['requesterUid'].toString(), exceptTeamId: teamId);
    final othersB = await commitmentsOf(uid, exceptTeamId: teamId);
    final teamRef = _db.collection(teamsCol).doc(teamId);
    await _db.runTransaction((tx) async {
      final r = (await tx.get(reqRef)).data();
      final team = (await tx.get(teamRef)).data();
      if (r == null ||
          team == null ||
          r['status'] != 'pending' ||
          r['type'] != 'swap') {
        throw Exception('This request is already closed.');
      }
      if (r['targetUid'] != uid) {
        throw Exception('This swap was not offered to you.');
      }
      final a = DutySlot.parse(r['sourceKey'].toString());
      final b = DutySlot.parse(r['targetKey'].toString());
      if (a == null || b == null) throw Exception('This request is not valid.');
      final roster = rosterOf(team);
      final check = roster.checkSwap(
          r['requesterUid'].toString(), a, uid, b, DateTime.now(),
          othersA: othersA, othersB: othersB);
      if (!check.ok) throw Exception(check.problem);
      final myName = nameOf(team, uid);
      tx.update(teamRef, {
        'overrides.${a.key}': uid,
        'overrides.${b.key}': r['requesterUid'],
        'overrideNames.${a.key}': myName,
        'overrideNames.${b.key}': r['requesterName'],
      });
      tx.update(reqRef, {
        'status': 'accepted',
        'acceptedBy': uid,
        'acceptedByName': myName,
        'resolvedAt': DateTime.now().toIso8601String(),
      });
    });
  }
}
