import 'app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/safe_cast.dart';

import 'pricing_service.dart';

/// Care Physician Agency Control Room (handover v1).
///
/// An agency (agencies/{uid}, agencyType 'care_physician') places its care
/// physicians in hospitals as permanent staff, locum (shift) cover or
/// emergency locum. Collections:
///   agencies/{agencyId}          name, city, phone, splitDoctorPct 80,
///                                splitAgencyPct 15, splitAppPct 5
///   agency_doctors/{doctorId}    agencyId, name, phone, qualification, regNo,
///                                placementType 'pool' | 'permanent',
///                                permanentHospitalId/Name, permanentSince,
///                                leaveFrom, leaveTo, active, userUid
///   agency_hospitals/{id}        agencyId, name, area, contactName, contactPhone
///   duties/{dutyId}              agencyId, doctorId, doctorName, hospitalId,
///                                hospitalName, type, unit, date, shiftStart,
///                                shiftEnd, status, checkInAt, checkOutAt,
///                                lateMinutes, hospitalRate, doctorPay,
///                                agencyShare, appShare, payoutStatus, paidAt
/// ('doctors' and 'hospitals' already hold the app's own providers, so the
/// agency's lists use the agency_ prefix.)
class CareAgencyService {
  static FirebaseFirestore get _db => AppDatabase.instance;

  static const String agencyTypeCare = 'care_physician';
  static const String agencyTypePhysio = 'physio';
  static const String agencyTypeNurse = 'nurse';
  static const String agencyTypeTechnician = 'technician';

  static const int lateAfterMinutes = 15;
  static const Duration absentAfter = Duration(hours: 4);
  static const Duration checkInOpensBefore = Duration(hours: 1);

  static const List<String> dutyTypes = ['locum', 'emergency', 'permanent'];
  static const List<String> units = ['ward', 'icu', 'casualty', 'night'];
  static const List<String> qualifications = ['MBBS', 'BAMS', 'BHMS'];

  static const Map<String, String> typeLabels = {
    'locum': 'Locum',
    'emergency': 'Emergency locum',
    'permanent': 'Permanent',
  };
  static const Map<String, String> unitLabels = {
    'ward': 'Ward',
    'icu': 'ICU',
    'casualty': 'Casualty',
    'night': 'Night',
  };

  // ---------------------------------------------------------------- dates

  /// 'yyyy-MM-dd' for a local date (the agency works in Asia/Kolkata).
  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseKey(String? key) {
    final p = (key ?? '').split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime? asTime(dynamic raw) => raw is Timestamp
      ? raw.toDate()
      : (raw is DateTime ? raw : DateTime.tryParse((raw ?? '').toString()));

  /// First and last date key of 'today' / 'week' (Mon–Sun) / 'month'.
  static ({String from, String to}) periodRange(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'week':
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (
          from: dateKey(monday),
          to: dateKey(monday.add(const Duration(days: 6)))
        );
      case 'month':
        return (
          from: dateKey(DateTime(today.year, today.month, 1)),
          to: dateKey(DateTime(today.year, today.month + 1, 0))
        );
      default:
        return (from: dateKey(today), to: dateKey(today));
    }
  }

  // ---------------------------------------------------------------- money

  /// Shares of a duty's hospital rate. App share absorbs rounding.
  static ({int doctorPay, int agencyShare, int appShare}) split(
      num hospitalRate, Map<String, dynamic> agency) {
    final rate = hospitalRate.round();
    final doctorPct = toNum(agency['splitDoctorPct']) ?? 80;
    final agencyPct = toNum(agency['splitAgencyPct']) ?? 15;
    final doctorPay = (rate * doctorPct / 100).round();
    final agencyShare = (rate * agencyPct / 100).round();
    return (
      doctorPay: doctorPay,
      agencyShare: agencyShare,
      appShare: rate - doctorPay - agencyShare,
    );
  }

  // --------------------------------------------------------- duty status

  /// Live state of a duty for the lists:
  /// cancelled / absent / completed / on_duty / late / scheduled.
  static String dutyState(Map<String, dynamic> duty, DateTime now) {
    final status = (duty['status'] ?? 'scheduled').toString();
    if (status == 'cancelled' || status == 'absent') return status;
    if (duty['checkOutAt'] != null || status == 'completed') return 'completed';
    if (duty['checkInAt'] != null || status == 'on_duty') return 'on_duty';
    final start = asTime(duty['shiftStart']);
    if (start != null &&
        now.isAfter(start.add(const Duration(minutes: lateAfterMinutes)))) {
      return 'late';
    }
    return 'scheduled';
  }

  /// Minutes late: for a check-in made >15 min after the start, or for a
  /// duty still not checked in >15 min after the start. 0 otherwise.
  static int lateMinutes(Map<String, dynamic> duty, DateTime now) {
    final start = asTime(duty['shiftStart']);
    if (start == null) return 0;
    final checkIn = asTime(duty['checkInAt']);
    final state = dutyState(duty, now);
    if (checkIn == null && state != 'late') return 0;
    final mins = (checkIn ?? now).difference(start).inMinutes;
    return mins > lateAfterMinutes ? mins : 0;
  }

  /// Still not checked in 4 h after the start: becomes absent.
  static bool shouldAutoAbsent(Map<String, dynamic> duty, DateTime now) {
    if ((duty['status'] ?? 'scheduled') != 'scheduled') return false;
    if (duty['checkInAt'] != null) return false;
    final start = asTime(duty['shiftStart']);
    return start != null && now.isAfter(start.add(absentAfter));
  }

  static bool isOnLeave(Map<String, dynamic> doctor, String dayKey) {
    final from = (doctor['leaveFrom'] ?? '').toString();
    final to = (doctor['leaveTo'] ?? '').toString();
    if (from.isEmpty || to.isEmpty) return false;
    return from.compareTo(dayKey) <= 0 && dayKey.compareTo(to) <= 0;
  }

  // ------------------------------------------------------------- summary

  static ControlRoomSummary summarize({
    required List<Map<String, dynamic>> doctors,
    required List<Map<String, dynamic>> periodDuties,
    required DateTime now,
  }) {
    final todayKey = dateKey(now);
    final active = doctors.where((d) => d['active'] != false).toList();
    final today =
        periodDuties.where((d) => d['date'] == todayKey).toList();
    final todayLive = today.where((d) => d['status'] != 'cancelled').toList();
    final s = ControlRoomSummary();

    s.totalDoctors = active.length;
    s.permanentPlaced =
        active.where((d) => d['placementType'] == 'permanent').length;
    s.onLeave = active.where((d) => isOnLeave(d, todayKey)).length;

    final busy = {for (final d in todayLive) d['doctorId']};
    s.noJobToday = active
        .where((d) =>
            !busy.contains(d['id']) &&
            d['placementType'] != 'permanent' &&
            !isOnLeave(d, todayKey))
        .length;

    for (final d in periodDuties) {
      final status = d['status'];
      if (status == 'cancelled') continue;
      if (d['type'] == 'locum') s.locumSent++;
      if (d['type'] == 'emergency') s.emergencyLocum++;
      if (status == 'absent') continue; // absent duties are not billed
      s.billed += toNum(d['hospitalRate']) ?? 0;
      final pay = toNum(d['doctorPay']) ?? 0;
      s.doctorPayouts += pay;
      if (d['payoutStatus'] == 'paid') {
        s.doctorPaid += pay;
      } else {
        s.doctorDue += pay;
      }
      s.agencyShare += toNum(d['agencyShare']) ?? 0;
      s.appShare += toNum(d['appShare']) ?? 0;
    }

    for (final d in todayLive) {
      switch (dutyState(d, now)) {
        case 'on_duty':
          s.onDutyNow++;
        case 'late':
          s.late++;
        case 'absent':
          s.absent++;
        case 'completed':
          s.completed++;
      }
      // check-ins made more than 15 min late also count as late
      if (dutyState(d, now) != 'late' &&
          d['checkInAt'] != null &&
          lateMinutes(d, now) > 0) {
        s.late++;
      }
    }
    return s;
  }

  // ----------------------------------------------------------- Firestore

  static List<Map<String, dynamic>> _withIds(
          QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) {...d.data(), 'id': d.id}];

  static Stream<Map<String, dynamic>> agencyStream(String agencyId) => _db
      .collection('agencies')
      .doc(agencyId)
      .snapshots()
      .map((d) => {...?d.data(), 'id': d.id});

  static Stream<List<Map<String, dynamic>>> doctorsStream(String agencyId) =>
      _db
          .collection('agency_doctors')
          .where('agencyId', isEqualTo: agencyId)
          .snapshots()
          .map((s) => _withIds(s)
            ..sort((a, b) => (a['name'] ?? '')
                .toString()
                .toLowerCase()
                .compareTo((b['name'] ?? '').toString().toLowerCase())));

  static Stream<List<Map<String, dynamic>>> hospitalsStream(String agencyId) =>
      _db
          .collection('agency_hospitals')
          .where('agencyId', isEqualTo: agencyId)
          .snapshots()
          .map((s) => _withIds(s)
            ..sort((a, b) => (a['name'] ?? '')
                .toString()
                .compareTo((b['name'] ?? '').toString())));

  /// Duties of the agency from [from] to [to] (date keys, inclusive).
  /// Needs the composite index duties (agencyId, date).
  static Stream<List<Map<String, dynamic>>> dutiesStream(
          String agencyId, String from, String to) =>
      _db
          .collection('duties')
          .where('agencyId', isEqualTo: agencyId)
          .where('date', isGreaterThanOrEqualTo: from)
          .where('date', isLessThanOrEqualTo: to)
          .snapshots()
          .map(_withIds);

  /// Every agency's duties between two dates (the admin's earnings).
  static Stream<List<Map<String, dynamic>>> dutiesBetweenStream(
          String from, String to) =>
      _db
          .collection('duties')
          .where('date', isGreaterThanOrEqualTo: from)
          .where('date', isLessThanOrEqualTo: to)
          .snapshots()
          .map(_withIds);

  static String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  static Future<void> saveDoctor(String agencyId, Map<String, dynamic> data,
      {String? id}) async {
    final payload = {
      ...data,
      'agencyId': agencyId,
      'phone': normalizePhone((data['phone'] ?? '').toString()),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (id == null) {
      await _db.collection('agency_doctors').add({
        ...payload,
        'active': data['active'] ?? true,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      await _db
          .collection('agency_doctors')
          .doc(id)
          .set(payload, SetOptions(merge: true));
    }
  }

  static Future<void> saveHospital(String agencyId, Map<String, dynamic> data,
      {String? id}) async {
    final payload = {
      ...data,
      'agencyId': agencyId,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (id == null) {
      await _db.collection('agency_hospitals').add({
        ...payload,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      await _db
          .collection('agency_hospitals')
          .doc(id)
          .set(payload, SetOptions(merge: true));
    }
  }

  /// Shift times for [day] from 'HH:mm' strings; an end at or before the
  /// start ends the next day (night shift).
  static ({DateTime start, DateTime end}) shiftTimes(
      DateTime day, String startHm, String endHm) {
    DateTime at(String hm) {
      final p = hm.split(':');
      return DateTime(day.year, day.month, day.day, int.parse(p[0]),
          int.parse(p[1]));
    }

    final start = at(startHm);
    var end = at(endHm);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start: start, end: end);
  }

  /// Rate fields of a duty: the agency's [baseRate], and the rate billed to
  /// the hospital (an emergency locum is billed with the hike from
  /// app_settings/pricing). The server applies the same rule.
  static Map<String, dynamic> rateFields(
      String type, num baseRate, PricingSettings pricing) {
    final billed = pricing.billedRate(type, baseRate);
    return {
      'baseRate': baseRate.round(),
      'hospitalRate': billed,
      if (billed != baseRate.round())
        'emergencyHikePct': pricing.emergencyLocumHikePct,
    };
  }

  /// Creates a duty; the money shares are written from the agency split.
  static Future<void> createDuty({
    required Map<String, dynamic> agency,
    required Map<String, dynamic> doctor,
    required Map<String, dynamic> hospital,
    required String type,
    required String unit,
    required DateTime day,
    required String startHm,
    required String endHm,
    required num hospitalRate,
  }) async {
    final times = shiftTimes(day, startHm, endHm);
    final rates =
        rateFields(type, hospitalRate, await PricingService.load());
    final shares = split(rates['hospitalRate'] as num, agency);
    await _db.collection('duties').add({
      'agencyId': agency['id'],
      'doctorId': doctor['id'],
      'doctorName': doctor['name'] ?? '',
      'doctorUserUid': doctor['userUid'],
      'hospitalId': hospital['id'],
      'hospitalName': hospital['name'] ?? '',
      'type': type,
      'unit': unit,
      'date': dateKey(day),
      'shiftStart': Timestamp.fromDate(times.start),
      'shiftEnd': Timestamp.fromDate(times.end),
      'status': 'scheduled',
      ...rates,
      'doctorPay': shares.doctorPay,
      'agencyShare': shares.agencyShare,
      'appShare': shares.appShare,
      'payoutStatus': 'due',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }


  static Future<void> setDutyStatus(String dutyId, String status) =>
      _db.collection('duties').doc(dutyId).update({
        'status': status,
        if (status == 'absent') 'absentMarkedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

  /// 4 h after the start with no check-in: absent (also done by the
  /// scheduled Cloud Function). Returns how many were marked.
  static Future<int> autoMarkAbsent(
      List<Map<String, dynamic>> duties, DateTime now) async {
    var marked = 0;
    for (final d in duties) {
      if (!shouldAutoAbsent(d, now)) continue;
      final ref = _db.collection('duties').doc(d['id'].toString());
      final ok = await _db.runTransaction<bool>((tx) async {
        final fresh = (await tx.get(ref)).data();
        if (fresh == null || !shouldAutoAbsent(fresh, now)) return false;
        tx.update(ref, {
          'status': 'absent',
          'absentMarkedAt': now.toIso8601String(),
          'autoAbsent': true,
        });
        return true;
      });
      if (ok) marked++;
    }
    return marked;
  }

  /// Month end: marks the doctor payouts of these duties as paid.
  static Future<void> markPaid(Iterable<String> dutyIds) async {
    final ids = dutyIds.toList();
    for (var i = 0; i < ids.length; i += 400) {
      final batch = _db.batch();
      for (final id in ids.skip(i).take(400)) {
        batch.update(_db.collection('duties').doc(id), {
          'payoutStatus': 'paid',
          'paidAt': DateTime.now().toIso8601String(),
        });
      }
      await batch.commit();
    }
  }

  // ------------------------------------------------------- doctor app

  /// Agency doctor records of an app doctor: matched by login uid, or by
  /// mobile number (then linked to the uid).
  static Future<List<String>> linkDoctorRecords(
      String uid, String phone) async {
    final ids = <String>{};
    final byUid = await _db
        .collection('agency_doctors')
        .where('userUid', isEqualTo: uid)
        .get();
    ids.addAll(byUid.docs.map((d) => d.id));
    final p = normalizePhone(phone);
    if (p.length == 10) {
      final byPhone = await _db
          .collection('agency_doctors')
          .where('phone', isEqualTo: p)
          .get();
      for (final d in byPhone.docs) {
        if (d.data()['userUid'] == null) {
          await d.reference.update({'userUid': uid});
        }
        if (d.data()['userUid'] == null || d.data()['userUid'] == uid) {
          ids.add(d.id);
        }
      }
    }
    return ids.toList();
  }

  /// Today's (and last night's) duties for these agency doctor records.
  static Stream<List<Map<String, dynamic>>> myDutiesStream(
      List<String> doctorIds, DateTime now) {
    if (doctorIds.isEmpty) return Stream.value(const []);
    final today = dateKey(now);
    final yesterday = dateKey(now.subtract(const Duration(days: 1)));
    // One duty a day per doctor, so the date is filtered here (no index)
    return _db
        .collection('duties')
        .where('doctorId', whereIn: doctorIds.take(30).toList())
        .snapshots()
        .map((s) => _withIds(s)
            .where((d) =>
                (d['date'] == today || d['date'] == yesterday) &&
                d['status'] != 'cancelled' &&
                (d['date'] == today ||
                    // a night shift from yesterday still running
                    (asTime(d['shiftEnd'])?.isAfter(now) ?? false)))
            .toList()
          ..sort((a, b) => (asTime(a['shiftStart']) ?? now)
              .compareTo(asTime(b['shiftStart']) ?? now)));
  }

  static bool canCheckIn(Map<String, dynamic> duty, DateTime now) {
    if (duty['checkInAt'] != null) return false;
    if ((duty['status'] ?? 'scheduled') != 'scheduled') return false;
    final start = asTime(duty['shiftStart']);
    final end = asTime(duty['shiftEnd']);
    if (start == null || end == null) return false;
    return !now.isBefore(start.subtract(checkInOpensBefore)) &&
        now.isBefore(end);
  }

  static bool canCheckOut(Map<String, dynamic> duty) =>
      duty['checkInAt'] != null && duty['checkOutAt'] == null;

  static Future<int> checkIn(String dutyId) async {
    final ref = _db.collection('duties').doc(dutyId);
    return _db.runTransaction<int>((tx) async {
      final d = (await tx.get(ref)).data();
      final now = DateTime.now();
      if (d == null || !canCheckIn(d, now)) {
        throw Exception('Check-in is open from 1 hour before your shift until it ends.');
      }
      final start = asTime(d['shiftStart'])!;
      final late = now.difference(start).inMinutes;
      tx.update(ref, {
        'checkInAt': Timestamp.fromDate(now),
        'status': 'on_duty',
        'lateMinutes': late > lateAfterMinutes ? late : 0,
      });
      return late > lateAfterMinutes ? late : 0;
    });
  }

  static Future<void> checkOut(String dutyId) async {
    final ref = _db.collection('duties').doc(dutyId);
    await _db.runTransaction((tx) async {
      final d = (await tx.get(ref)).data();
      if (d == null || !canCheckOut(d)) {
        throw Exception('Check in first, then check out at the end of the shift.');
      }
      tx.update(ref, {
        'checkOutAt': Timestamp.fromDate(DateTime.now()),
        'status': 'completed',
      });
    });
  }
}

/// Numbers on the Control Room.
class ControlRoomSummary {
  // 1 · Doctor pool
  int totalDoctors = 0;
  int permanentPlaced = 0;
  int locumSent = 0;
  int emergencyLocum = 0;
  // 2 · Today's attendance
  int onDutyNow = 0;
  int late = 0;
  int absent = 0;
  int completed = 0;
  int noJobToday = 0;
  int onLeave = 0;
  // 3 · Money (period)
  num billed = 0;
  num doctorPayouts = 0;
  num doctorPaid = 0;
  num doctorDue = 0;
  num agencyShare = 0;
  num appShare = 0;
}
