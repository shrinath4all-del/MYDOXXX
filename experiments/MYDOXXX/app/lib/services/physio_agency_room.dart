import 'app_database.dart';
import '../utils/safe_cast.dart';

import 'firestore_service.dart';
import 'physio_agency_service.dart';

/// Physio agency Control Room: the same screen as the care physician
/// agency, with the agency's physio team and the home visits routed to it
/// (appointments where agencyId == the agency).
class PhysioAgencyRoom {
  static const double appPct = 10; // platform share of each payment
  static const double defaultCommissionPct =
      PhysioAgencyService.defaultCommissionPct;

  /// Home visits routed to this agency (accepted by its team or still
  /// waiting in the agency window).
  static Stream<List<Map<String, dynamic>>> visitsStream(String agencyId) =>
      AppDatabase.instance
          .collection('appointments')
          .where('agencyId', isEqualTo: agencyId)
          .snapshots()
          .map((s) => [for (final d in s.docs) {...d.data(), 'id': d.id}]);

  static String dayOf(Map<String, dynamic> visit) =>
      FirestoreService.normalizeDateKey((visit['date'] ?? '').toString());

  /// offered / accepted / in_progress / completed / absent / closed
  static String visitState(Map<String, dynamic> v, DateTime now) {
    switch ((v['status'] ?? '').toString()) {
      case 'Broadcasted':
        return PhysioAgencyService.isAgencyWindowOpen(v, now: now)
            ? 'offered'
            : 'closed';
      case 'Confirmed':
        return 'accepted';
      case 'In Progress':
        return 'in_progress';
      case 'Completed':
        return 'completed';
      case 'Provider Absent':
        return 'absent';
      default:
        return 'closed'; // cancelled / declined / expired
    }
  }

  /// Started 30+ min late, or accepted and still not started 30 min after
  /// the booked time.
  static bool isLate(Map<String, dynamic> v, DateTime now) {
    if (v['lateArrival'] == true) return true;
    if (v['status'] != 'Confirmed') return false;
    final expected = FirestoreService.expectedArrival(v, now: now);
    return expected != null &&
        now.isAfter(expected.add(const Duration(
            minutes: FirestoreService.lateArrivalGraceMinutes)));
  }

  static int lateMinutes(Map<String, dynamic> v, DateTime now) {
    final stored = toNum(v['lateByMinutes'])?.toInt();
    if (stored != null && stored > 0) return stored;
    final expected = FirestoreService.expectedArrival(v, now: now);
    if (expected == null) return 0;
    final m = now.difference(expected).inMinutes;
    return m > 0 ? m : 0;
  }

  /// App 10% (or the Razorpay platform fee), agency commission on the rest,
  /// physio the remainder.
  static ({num billed, num app, num agency, num physio}) split(
      Map<String, dynamic> visit, Map<String, dynamic> agency) {
    final price = toNum(visit['price']) ?? 0;
    final app = toNum(visit['platformFee']) ?? (price * appPct / 100).round();
    final pro = price - app;
    final pct = toNum(agency['commissionPct']) ?? defaultCommissionPct;
    final agencyShare = (pro * pct / 100).round();
    return (billed: price, app: app, agency: agencyShare, physio: pro - agencyShare);
  }

  static String teamMode(Map<String, dynamic> physio, String agencyId) {
    if (physio['isVerified'] != true) return 'unverified';
    if (PhysioAgencyService.isOnAgencyDuty(physio, agencyId)) return 'on_duty';
    if (physio['workMode'] == 'offline' || physio['isOnline'] == false) {
      return 'offline';
    }
    return 'freelance';
  }

  static PhysioRoomSummary summarize({
    required String agencyId,
    required Map<String, dynamic> agency,
    required List<Map<String, dynamic>> team,
    required List<Map<String, dynamic>> visits,
    required String from,
    required String to,
    required DateTime now,
  }) {
    final s = PhysioRoomSummary();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    s.teamSize = team.length;
    for (final p in team) {
      switch (teamMode(p, agencyId)) {
        case 'on_duty':
          s.onAgencyDuty++;
        case 'freelance':
          s.freelanceNow++;
        default:
          s.offline++;
      }
    }

    for (final v in visits) {
      final day = dayOf(v);
      final state = visitState(v, now);
      final inPeriod = day.compareTo(from) >= 0 && day.compareTo(to) <= 0;
      if (inPeriod && state != 'closed' && state != 'offered') {
        s.visitsAccepted++;
      }
      if (inPeriod && state == 'completed') {
        final m = split(v, agency);
        s.billed += m.billed;
        s.appShare += m.app;
        s.agencyShare += m.agency;
        s.physioPayouts += m.physio;
      }
      if (day != todayKey) {
        if (state == 'offered') s.offeredNow++; // offers for later dates
        continue;
      }
      switch (state) {
        case 'offered':
          s.offeredNow++;
        case 'accepted':
          s.accepted++;
        case 'in_progress':
          s.inProgress++;
        case 'completed':
          s.completed++;
        case 'absent':
          s.absent++;
      }
      if ((state == 'accepted' || state == 'in_progress' ||
              state == 'completed') &&
          isLate(v, now)) {
        s.late++;
      }
    }
    return s;
  }
}

class PhysioRoomSummary {
  // 1 · Physio team
  int teamSize = 0;
  int onAgencyDuty = 0;
  int freelanceNow = 0;
  int offline = 0;
  int visitsAccepted = 0; // in the period
  // 2 · Today's visits
  int offeredNow = 0;
  int accepted = 0;
  int inProgress = 0;
  int completed = 0;
  int late = 0;
  int absent = 0;
  // 3 · Money (completed visits in the period)
  num billed = 0;
  num physioPayouts = 0;
  num agencyShare = 0;
  num appShare = 0;
}
