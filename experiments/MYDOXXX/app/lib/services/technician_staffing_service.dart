import 'service_otp.dart';
import 'staffing_claim_agency.dart';
import 'app_database.dart';
import 'lab_device.dart';
import 'dart:async';
import '../utils/lab_test_groups.dart';
import '../utils/safe_cast.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/care_duty_roster.dart';
import 'technician_duty_rate_service.dart';
import 'technician_duty_service.dart';
import 'sos_service.dart';

import 'care_agency_service.dart';
import 'firestore_service.dart';
import 'pricing_service.dart';
import '../utils/ist_clock.dart';
import '../utils/ist_timestamp.dart';

/// Technician marketplace (the care physician / nurse flow for lab,
/// radiology, ECG, EEG, OT and other technicians).
///
///   * Hospitals, technician agencies and the admin post **shifts**
///     (one duty, paid per shift) and **full-time jobs** (monthly salary).
///   * A technician (role 'technician', collection
///     `care_physicians/{uid}`) sees the shifts and jobs that fit the
///     profile (duty types, areas, qualification), claims a shift (first to
///     confirm gets it) and checks in / out on the day; for a job they
///     express interest and the poster contacts them.
///   * An agency's shift becomes a duty in the agency's Control Room when it
///     is claimed (money split, attendance), and check-in / out is copied to
///     that duty.
///
/// Collections: `shifts/{id}`, `jobs/{id}` (+ `jobs/{id}/interests/{uid}`).
/// Every query is a single equality filter, so no composite index is needed.
class TechnicianStaffingService {
  TechnicianStaffingService._();

  static FirebaseFirestore get _db => AppDatabase.instance;

  static const String collection = 'technicians';
  static const String shiftsCol = 'technician_shifts';
  static const String jobsCol = 'technician_jobs';

  /// Repeated no-shows suspend claiming.
  static const int maxNoShows = 3;
  static const Duration absentAfter = Duration(hours: 4);
  static const Duration checkInOpensBefore = Duration(hours: 1);
  /// Travel buffer: arriving up to 45 min after the booked time is on time.
  static const int lateAfterMinutes = 45;

  // ------------------------------------------------------------- options

  /// key -> (label, note)
  static const Map<String, (String, String)> qualifications = {
    'DMLT': ('DMLT', 'Diploma in Medical Lab Technology'),
    'BMLT': ('B.Sc MLT', 'Bachelor of Medical Lab Technology'),
    'MMLT': ('M.Sc MLT', 'Master of Medical Lab Technology'),
    'DRT': ('DRT / X-Ray', 'Diploma in Radiology Technology'),
    'Cardiac Tech': ('Cardiac Tech', 'ECG / Echo / TMT technology'),
    'OT Tech': ('OT Tech', 'Operation theatre technology'),
    'Dialysis Tech': ('Dialysis Tech', 'Dialysis technology'),
  };

  /// The tests a technician can do and a hospital can ask for: the lab
  /// tests patients book (`lab_tests`), keyed by name (the same names as
  /// the technician's `offeredTests`, which patient bookings match).
  /// key -> (emoji, label, needs verified credentials). Filled by
  /// [loadProcedures]; these are shown until it has run.
  static final Map<String, (String, String, bool)> procedures = {
    'EEG': ('🧠', 'EEG', false),
    'NCS': ('🧠', 'NCS', false),
    'EMG': ('🧠', 'EMG', false),
    'ECG': ('🧪', 'ECG', false),
    'X-Ray': ('🧪', 'X-Ray', false),
    'Lab - Blood Draw': ('🩸', 'Lab - Blood Draw', false),
  };

  /// test name -> its group (LabTestGroups: neuro, blood, other).
  static final Map<String, String> procedureGroups = {
    'EEG': LabTestGroups.neuro,
    'NCS': LabTestGroups.neuro,
    'EMG': LabTestGroups.neuro,
    'Lab - Blood Draw': LabTestGroups.other,
  };

  /// The tests by group, in display order (Neuro technician, Blood tests,
  /// Other tests).
  static List<(String, List<String>)> groupedProcedures() => [
        for (final g in LabTestGroups.order)
          (
            g,
            [
              for (final k in procedures.keys)
                if ((procedureGroups[k] ?? LabTestGroups.other) == g) k
            ]
          ),
      ].where((e) => e.$2.isNotEmpty).toList();

  static Future<void>? _proceduresLoad;

  /// Reads the lab tests once (screens call it before showing the list).
  static Future<void> loadProcedures() =>
      _proceduresLoad ??= _loadProcedures().catchError((_) {
        _proceduresLoad = null; // try again next time
      });

  static Future<void> _loadProcedures() async {
    final tests = await FirestoreService.getLabTestsWithPrice();
    final named = [
      for (final t in tests)
        if ((t['name'] ?? '').toString().trim().isNotEmpty) t
    ];
    if (named.isEmpty) return;
    String emoji(String group) => switch (group) {
          LabTestGroups.neuro => '🧠',
          LabTestGroups.blood => '🩸',
          _ => '🧪',
        };
    procedures.clear();
    procedureGroups.clear();
    for (final t in named) {
      final n = t['name'].toString().trim();
      final g = (t['category'] ?? LabTestGroups.other).toString();
      procedures[n] = (emoji(g), n, false);
      procedureGroups[n] = g;
    }
  }

  static const Map<String, (String, String)> ageGroups = {
    'adult': ('🧑', 'Adult care'),
    'paediatric': ('🧒', 'Paediatric'),
    'neonatal': ('👶', 'Neonatal'),
    'geriatric': ('🧓', 'Geriatric'),
  };

  /// Departments a technician works in.
  static const Map<String, (String, String)> specialties = {
    'pathology': ('🧫', 'Pathology lab'),
    'radiology': ('🩻', 'X-Ray / Imaging'),
    'cardiology': ('❤️', 'ECG / Echo / TMT'),
    'neurology': ('🧠', 'EEG / NCS / EMG'),
    'ot': ('🔪', 'Operation theatre'),
    'dialysis': ('💧', 'Dialysis'),
    'audiology': ('👂', 'Audiometry'),
  };

  /// key -> (emoji, label, description)
  static const Map<String, (String, String, String)> dutyTypes = {
    'home': ('🏠', 'Home sample collection', 'Collect samples / do tests at a patient\'s home'),
    'ward': ('🧪', 'Lab duty', 'Hospital lab / sample collection cover'),
    'icu': ('🫀', 'ICU duty', 'ICU technician cover (ABG, bedside tests)'),
    'specialty': ('⭐', 'Department duty', 'X-Ray, ECG, EEG, OT, dialysis… cover'),
    'casualty': ('🚨', 'Casualty / ER', 'Emergency room technician cover'),
  };

  /// Shift slots: key -> (label, start, end)
  static const Map<String, (String, String, String)> slots = {
    'morning': ('Good morning', '08:00', '14:00'),
    'evening': ('Good afternoon', '14:00', '20:00'),
    'night': ('Good evening', '20:00', '08:00'),
  };

  /// Full-time job timings: key -> (emoji, label)
  static const Map<String, (String, String)> jobTimings = {
    'morning': ('🌅', 'Morning'),
    'afternoon': ('☀️', 'Afternoon'),
    'evening': ('🌆', 'Evening'),
    'full_time': ('🔄', 'Full Time'),
  };

  static String dutyLabel(String? key) => dutyTypes[key]?.$2 ?? 'Duty';
  static String dutyEmoji(String? key) => dutyTypes[key]?.$1 ?? '🩺';
  static String specialtyLabel(String? key) => specialties[key]?.$2 ?? '';

  static List<String> listOf(dynamic raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : const [];

  // ------------------------------------------------------------- times

  static String dateKey(DateTime d) => CareAgencyService.dateKey(d);

  static DateTime? _at(String date, String hhmm) {
    final day = CareAgencyService.parseKey(date);
    final parts = hhmm.split(':');
    if (day == null || parts.length != 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static DateTime? shiftStart(Map<String, dynamic> s) =>
      _at((s['date'] ?? '').toString(), (s['start'] ?? '').toString());

  /// End time; an end at or before the start is the next morning.
  static DateTime? shiftEnd(Map<String, dynamic> s) {
    final start = shiftStart(s);
    final end =
        _at((s['date'] ?? '').toString(), (s['end'] ?? '').toString());
    if (start == null || end == null) return null;
    return end.isAfter(start) ? end : end.add(const Duration(days: 1));
  }

  /// "Tonight" / "Today" / "Tomorrow" / "Sun, 23 Aug".
  static String dayLabel(Map<String, dynamic> s, DateTime now) {
    final start = shiftStart(s);
    if (start == null) return (s['date'] ?? '').toString();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(start.year, start.month, start.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return start.hour >= 18 ? 'Tonight' : 'Today';
    if (diff == 1) return 'Tomorrow';
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
      'Oct', 'Nov', 'Dec'];
    return '${wd[start.weekday - 1]}, ${start.day} ${mo[start.month - 1]}';
  }

  /// "8 AM – 2 PM"
  static String timeRange(Map<String, dynamic> s) {
    String fmt(DateTime? t) {
      if (t == null) return '—';
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
      return '$h$m ${t.hour < 12 ? 'AM' : 'PM'}';
    }

    return '${fmt(shiftStart(s))} – ${fmt(shiftEnd(s))}';
  }

  static String slotLabel(Map<String, dynamic> s) =>
      s['slot'] == 'visit' ? 'Home visit' : (slots[s['slot']]?.$1 ?? 'Shift');

  // ------------------------------------------------------------- matching

  static bool isVerified(Map<String, dynamic> p) => p['isVerified'] == true;

  static bool _fitsList(List<String> mine, String? value) =>
      mine.isEmpty || value == null || value.isEmpty || mine.contains(value);

  /// One of my areas covers [location] ("Wakad" covers "Wakad, Pune"), the
  /// same rule as technician / technician / physio bookings. No areas = any.
  static bool inMyAreas(List<String> mine, String? location) =>
      mine.isEmpty ||
      location == null ||
      location.trim().isEmpty ||
      FirestoreService.providerServesArea(mine, location);

  /// A patient's home visit goes first to the doctors of the agencies that
  /// serve the area, until 'agencyOfferUntil'.
  ///
  /// A hospital's shift ('agencyFirst') goes to technicians who belong to
  /// an agency for [hospitalAgencyFirst]; after that, freelancers see it too.
  static bool agencyWindowOpen(Map<String, dynamic> shift, DateTime now) {
    if (listOf(shift['offerAgencyIds']).isEmpty &&
        shift['agencyFirst'] != true) {
      return false;
    }
    final until = IstClock.tryParse((shift['agencyOfferUntil'] ?? '').toString());
    return until != null && now.isBefore(until);
  }

  /// An open shift the technician should see: not started yet, one of
  /// their duty types and areas (an empty choice means "any"); during an
  /// agency's first-offer window only that agency's doctors see it.
  static bool shiftFits(
      Map<String, dynamic> shift, Map<String, dynamic> me, DateTime now) {
    if (shift['status'] != 'open') return false;
    if (listOf(shift['declinedBy']).contains((me['uid'] ?? '').toString())) {
      return false;
    }
    if (isTeam(shift)) {
      // open to every technician; the best 10 go to the agency, which picks
      if (listOf(shift['applicantUids'])
          .contains((me['uid'] ?? '').toString())) {
        return false;
      }
      if (listOf(shift['allocatedUids']).length >=
          (toNum(shift['teamSize'])?.toInt() ?? 1)) {
        return false;
      }
    }
    final start = shiftStart(shift);
    if (start == null || !start.isAfter(now)) return false;
    if (agencyWindowOpen(shift, now)) {
      final myAgency = (me['agencyId'] ?? '').toString();
      if (shift['agencyFirst'] == true) {
        if (myAgency.isEmpty) return false; // agency doctors only, for now
      } else if (!listOf(shift['offerAgencyIds']).contains(myAgency)) {
        return false;
      }
    }
    return _fitsList(listOf(me['dutyTypes']), shift['dutyType']?.toString()) &&
        inMyAreas(listOf(me['areas'] ?? me['preferredLocations']), shift['area']?.toString());
  }

  /// The doctor may arrive up to [lateAfterMinutes] after the booked time
  /// (travel buffer) before it counts as late.
  static DateTime? reachBy(Map<String, dynamic> s) =>
      shiftStart(s)?.add(const Duration(minutes: lateAfterMinutes));

  /// "6:45 PM"
  static String clock(DateTime? t) {
    if (t == null) return '—';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Urgent first, then preferred hospitals, then soonest.
  static List<Map<String, dynamic>> sortShifts(
      List<Map<String, dynamic>> list, Map<String, dynamic> me) {
    final preferred = listOf(me['preferredHospitals']);
    int rank(Map<String, dynamic> s) =>
        (s['urgent'] == true ? 0 : 2) +
        (preferred.contains(s['hospitalName']) ? 0 : 1);
    return [...list]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return (shiftStart(a) ?? DateTime(2100))
            .compareTo(shiftStart(b) ?? DateTime(2100));
      });
  }

  static List<String> gatedOf(Iterable<String> keys) =>
      keys.where((k) => procedures[k]?.$3 == true).toList();

  static String procedureLabels(Iterable<String> keys) =>
      keys.map((k) => procedures[k]?.$2 ?? k).join(', ');

  /// Why the technician cannot claim [shift] now (null = can claim).
  static String? claimBlockReason(
    Map<String, dynamic> shift,
    Map<String, dynamic> me,
    List<Map<String, dynamic>> myShifts,
    DateTime now,
  ) {
    if ((toNum(me['noShows']) ?? 0) >= maxNoShows) {
      return 'Claiming is paused after repeated no-shows. Please contact support.';
    }
    if ((me['available'] == false || me['isOnline'] == false)) {
      return 'You are Off. Turn on Available to claim shifts.';
    }
    // ICU duty: verified credentials only, whatever the procedures
    if (shift['dutyType'] == 'icu' && !isVerified(me)) {
      return 'ICU duties need verified credentials. Your registration is '
          'still being verified.';
    }
    final needed = listOf(shift['procedures']);
    final gated = gatedOf(needed);
    if (gated.isNotEmpty && !isVerified(me)) {
      return 'This shift needs verified credentials (${procedureLabels(gated)}). '
          'Your registration is still being verified.';
    }
    if (!isVerified(me)) {
      return 'Your registration is pending verification. The admin is reviewing '
          'your documents. You can claim duties once it is approved.';
    }
    final mine = listOf(me['procedures']);
    final missing = needed.where((p) => !mine.contains(p)).toList();
    if (missing.isNotEmpty) {
      return 'This shift needs: ${procedureLabels(missing)}. Add it in your '
          'profile only if you are trained to do it.';
    }
    final start = shiftStart(shift), end = shiftEnd(shift);
    if (start != null && end != null) {
      for (final s in myShifts) {
        if (s['status'] != 'claimed' &&
            s['status'] != 'on_duty' &&
            s['status'] != 'pending_agency') {
          continue;
        }
        final a = shiftStart(s), b = shiftEnd(s);
        if (a != null && b != null && a.isBefore(end) && start.isBefore(b)) {
          return 'You already have a shift at that time '
              '(${s['hospitalName']}, ${timeRange(s)}).';
        }
      }
    }
    return null;
  }

  /// A full-time job that fits: active, in one of the areas and open to the
  /// qualification.
  static bool jobFits(Map<String, dynamic> job, Map<String, dynamic> me) {
    if (job['active'] == false) return false;
    final quals = listOf(job['qualifications']);
    final mine = (me['qualification'] ?? '').toString();
    return inMyAreas(listOf(me['areas'] ?? me['preferredLocations']), job['area']?.toString()) &&
        (quals.isEmpty || quals.contains(mine));
  }

  static bool hasInterest(Map<String, dynamic> job, String uid) =>
      listOf(job['interestedUids']).contains(uid);

  /// "₹60–80k" for monthly salaries.
  static String salaryLabel(Map<String, dynamic> job) {
    String k(num? v) {
      if (v == null || v <= 0) return '';
      final n = v / 1000;
      return n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);
    }

    final lo = k(toNum(job['salaryMin'])), hi = k(toNum(job['salaryMax']));
    if (lo.isEmpty && hi.isEmpty) return 'Salary on request';
    if (hi.isEmpty || lo == hi) return '₹${lo.isEmpty ? hi : lo}k';
    if (lo.isEmpty) return 'Up to ₹${hi}k';
    return '₹$lo–${hi}k';
  }

  // -------------------------------------------------------- duty states

  static bool canCheckIn(Map<String, dynamic> s, DateTime now) {
    if (s['status'] != 'claimed' || s['checkInAt'] != null) return false;
    final start = shiftStart(s), end = shiftEnd(s);
    if (start == null || end == null) return false;
    return !now.isBefore(start.subtract(checkInOpensBefore)) &&
        now.isBefore(end);
  }

  static bool canCheckOut(Map<String, dynamic> s) =>
      s['status'] == 'on_duty' && s['checkOutAt'] == null;

  /// Claimed, never checked in, 4 h after the start: a no-show.
  static bool isNoShow(Map<String, dynamic> s, DateTime now) {
    if (s['status'] != 'claimed' || s['checkInAt'] != null) return false;
    final start = shiftStart(s);
    return start != null && now.isAfter(start.add(absentAfter));
  }

  /// Earnings from claimed shifts (not cancelled / absent).
  /// What the doctor earns for [s]: on an agency's shift, the doctor's share
  /// after the agency's split; otherwise the full pay.
  static num doctorPayOf(Map<String, dynamic> s) =>
      toNum(s['doctorPay']) ?? toNum(s['pay']) ?? 0;

  /// The agency keeps part of [s]'s pay.
  static bool isAgencySplit(Map<String, dynamic> s) =>
      s['doctorPay'] != null && s['doctorPay'] != s['pay'];

  static int confirmedEarnings(List<Map<String, dynamic>> myShifts) =>
      myShifts
          .where((s) => const {'claimed', 'on_duty', 'completed'}
              .contains(s['status']))
          .fold<int>(0, (t, s) => t + doctorPayOf(s).round());

  // ----------------------------------------------------------- Firestore

  static List<Map<String, dynamic>> _withIds(
          QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) {...d.data(), 'id': d.id}];

  static Stream<Map<String, dynamic>> profileStream(String uid) => _db
      .collection(collection)
      .doc(uid)
      .snapshots()
      .map((d) => {...?d.data(), 'uid': d.id});

  // ---------------------------------------------------------- team requests

  /// A hospital asks for several technicians at once ('technician_team_requests').
  /// Agency technicians accept; the agency picks who goes (a shift is
  /// created and claimed for each one it picks).
  static const String teamCol = 'technician_team_requests';

  static bool isTeam(Map<String, dynamic> s) => s['isTeam'] == true;

  static int teamSizeOf(Map<String, dynamic> r) =>
      toNum(r['teamSize'])?.toInt() ?? 1;

  /// Both lists in one stream (each side emits at least once first).
  static Stream<List<Map<String, dynamic>>> _combine(
      Stream<List<Map<String, dynamic>>> a,
      Stream<List<Map<String, dynamic>>> b) {
    late StreamController<List<Map<String, dynamic>>> c;
    List<Map<String, dynamic>>? la, lb;
    final subs = <StreamSubscription<void>>[];
    void emit() {
      if (la != null && lb != null) c.add([...la!, ...lb!]);
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

  static List<Map<String, dynamic>> _teamsOf(
          QuerySnapshot<Map<String, dynamic>> s) =>
      [
        for (final d in s.docs) {...d.data(), 'id': d.id, 'isTeam': true}
      ];

  static Stream<List<Map<String, dynamic>>> openShiftsStream() => _combine(
      _db
          .collection(shiftsCol)
          .where('status', isEqualTo: 'open')
          .snapshots()
          .map(_withIds),
      _db
          .collection(teamCol)
          .where('status', isEqualTo: 'open')
          .snapshots()
          .map(_teamsOf));

  /// The doctor's duties, plus the team requests he accepted that the agency
  /// has not decided yet (status 'team_applied').
  /// The doctor's claimed duties. An application to a full-time team is not
  /// a duty: it shows in Applied until he is selected (then in the roster).
  static Stream<List<Map<String, dynamic>>> myShiftsStream(String uid) => _db
      .collection(shiftsCol)
      .where('claimedBy', isEqualTo: uid)
      .snapshots()
      .map((s) => _withIds(s)
        ..sort((a, b) => (shiftStart(b) ?? DateTime(2000))
            .compareTo(shiftStart(a) ?? DateTime(2000))));

  /// Every full-time team request the doctor applied to, newest first.
  static Stream<List<Map<String, dynamic>>> myApplicationsStream(String uid) => _db
      .collection(teamCol)
      .where('applicantUids', arrayContains: uid)
      .snapshots()
      .map((s) => _teamsOf(s)
        ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}')));

  /// Where an application stands for [uid]:
  ///   'selected'    placed in the team
  ///   'shortlisted' among the best 10, the agency is choosing
  ///   'applied'     applied, waiting
  ///   'not_selected' the team was placed without him
  ///   'closed'      the hospital cancelled it, or nobody was placed in time
  static String applicationStatus(Map<String, dynamic> request, String uid) {
    if (listOf(request['allocatedUids']).contains(uid)) return 'selected';
    final status = (request['status'] ?? '').toString();
    if (status == 'filled') return 'not_selected';
    if (status == 'cancelled' || status == 'unfilled') return 'closed';
    final start = shiftStart(request);
    if (start != null && !start.isAfter(IstClock.now())) return 'closed';
    return shortlist(request).any((e) => e.uid == uid) ? 'shortlisted' : 'applied';
  }

  /// A technician applies to a team request. Any technician can
  /// (agency or not); an existing duty on the same time does not stop the
  /// application: if he is placed, the clashing duty is released.
  ///
  /// [currentHospital]: a physician already placed at another hospital who
  /// applies to move (the agency sees where he works now).
  static Future<void> applyTeam(String id, Map<String, dynamic> me,
      {String currentHospital = ''}) async {
    final uid = me['uid'].toString();
    final mine =
        await _db.collection(shiftsCol).where('claimedBy', isEqualTo: uid).get();
    final ref = _db.collection(teamCol).doc(id);
    await _db.runTransaction((tx) async {
      final r = (await tx.get(ref)).data();
      if (r == null || r['status'] != 'open') {
        throw Exception('This team request is closed.');
      }
      final reason = r['rotation'] == true
          ? applyBlockReason(me)
          : claimBlockReason(r, me, _withIds(mine), IstClock.now());
      if (reason != null) throw Exception(reason);
      if (listOf(r['allocatedUids']).length >= teamSizeOf(r)) {
        throw Exception('The team is already full.');
      }
      tx.update(ref, {
        'applicantUids': FieldValue.arrayUnion([uid]),
        'applicants.$uid': {
          'name': (me['name'] ?? '').toString(),
          'phone': (me['phone'] ?? me['mobileNumber'] ?? '').toString(),
          'agencyId': (me['agencyId'] ?? '').toString(),
          'agencyName': (me['agencyName'] ?? '').toString(),
          'qualification': (me['qualification'] ?? '').toString(),
          'experienceYears': toNum(me['experienceYears'])?.round() ?? 0,
          'noShows': toNum(me['noShows'])?.round() ?? 0,
          if (currentHospital.isNotEmpty) 'currentHospital': currentHospital,
          'at': IstClock.now().toIso8601String(),
        },
      });
    });
  }

  /// Why a technician cannot apply to a full-time team (null = can).
  /// Existing duties are not a reason.
  static String? applyBlockReason(Map<String, dynamic> me) {
    if ((toNum(me['noShows']) ?? 0) >= maxNoShows) {
      return 'Applying is paused after repeated no-shows. Please contact support.';
    }
    if ((me['available'] == false || me['isOnline'] == false)) {
      return 'You are Off. Turn on Available to apply.';
    }
    if (!isVerified(me)) {
      return 'Your registration is pending verification. The admin is reviewing '
          'your documents. You can apply once it is approved.';
    }
    return null;
  }

  /// The best applicants of a team request, best first, at most [limit]
  /// (the shortlist sent to the agency): fewest no-shows, then most
  /// experience, then who applied first.
  static List<({String uid, Map<String, dynamic> data})> shortlist(
      Map<String, dynamic> request,
      {int limit = 10}) {
    final applicants = (request['applicants'] as Map?) ?? const {};
    final list = [
      for (final e in applicants.entries)
        if (e.value is Map &&
            !listOf(request['allocatedUids']).contains(e.key.toString()))
          (uid: e.key.toString(), data: Map<String, dynamic>.from(e.value as Map))
    ];
    int n(Map<String, dynamic> d, String k) => toNum(d[k])?.round() ?? 0;
    list.sort((a, b) {
      final ns = n(a.data, 'noShows').compareTo(n(b.data, 'noShows'));
      if (ns != 0) return ns;
      final ex = n(b.data, 'experienceYears').compareTo(n(a.data, 'experienceYears'));
      if (ex != 0) return ex;
      return '${a.data['at']}'.compareTo('${b.data['at']}');
    });
    return list.take(limit).toList();
  }

  /// A claimed shift is released: the technician no longer works it
  /// (he was placed in a full-time job at that time), and it opens again for
  /// other technicians. The hospital is told by the server.
  static Future<void> reopenShift(String shiftId, String uid, String reason) async {
    final ref = _db.collection(shiftsCol).doc(shiftId);
    await _db.runTransaction((tx) async {
      final s = (await tx.get(ref)).data();
      if (s == null || s['claimedBy'] != uid || s['status'] != 'claimed') return;
      final schedule = await tx.get(scheduleRef(uid));
      final dutyId = (s['dutyId'] ?? '').toString();
      tx.update(ref, {
        'status': 'open',
        'declinedBy': FieldValue.arrayUnion([uid]),
        'reopenedFrom': (s['claimedByName'] ?? '').toString(),
        'reopenedAt': IstClock.now().toIso8601String(),
        'reopenReason': reason,
        'claimedBy': FieldValue.delete(),
        'claimedByName': FieldValue.delete(),
        'claimedByPhone': FieldValue.delete(),
        'claimedAt': FieldValue.delete(),
        'claimedAgencyId': FieldValue.delete(),
        'claimedAgencyName': FieldValue.delete(),
        'agencyWatch': FieldValue.delete(),
        'dutyId': FieldValue.delete(),
        'arrivalOtp': FieldValue.delete(),
        'arrivalOtpAt': FieldValue.delete(),
        'pushedUids': FieldValue.delete(), // everyone who fits is told again
        'openToAllPushed': FieldValue.delete(),
      });
      if (dutyId.isNotEmpty) {
        tx.update(_db.collection('duties').doc(dutyId), {'status': 'cancelled'});
      }
      if (schedule.exists) {
        tx.update(schedule.reference, {'slots.$shiftId': FieldValue.delete()});
      }
    });
  }

  /// The agency sends [uids] (doctors of its own who accepted) to the
  /// hospital: each becomes a claimed shift and a duty in the Control Room.
  /// Returns the doctors that could not be allocated, with the reason.
  static Future<List<String>> allocateTeam(
      Map<String, dynamic> request, String agencyId, List<String> uids) async {
    final id = request['id'].toString();
    final ref = _db.collection(teamCol).doc(id);
    final fresh = (await ref.get()).data();
    if (fresh == null || fresh['status'] != 'open') {
      throw Exception('This team request is closed.');
    }
    final size = teamSizeOf(fresh);
    final done = listOf(fresh['allocatedUids']);
    if (uids.isEmpty) throw Exception('Pick at least one doctor.');
    if (done.length + uids.length > size) {
      throw Exception('Only ${size - done.length} more doctor(s) are needed.');
    }
    final applicants = (fresh['applicants'] as Map?) ?? const {};
    final failed = <String>[];
    final ok = <String>[];
    final names = <String>[];
    for (final uid in uids) {
      final a = applicants[uid] as Map?;
      if (a == null || a['agencyId'] != agencyId) {
        failed.add('$uid: not one of your doctors who accepted');
        continue;
      }
      final child = await _db.collection(shiftsCol).add({
        'postedBy': 'hospital',
        'posterId': fresh['posterId'],
        'posterName': fresh['posterName'],
        'hospitalId': fresh['hospitalId'],
        'hospitalName': fresh['hospitalName'],
        'area': fresh['area'],
        'dutyType': fresh['dutyType'],
        'specialty': fresh['specialty'] ?? '',
        'procedures': listOf(fresh['procedures']),
        'date': fresh['date'],
        'slot': fresh['slot'],
        'start': fresh['start'],
        'end': fresh['end'],
        'pay': fresh['pay'],
        for (final k in const [
          'doctorPay', 'marginAmount', 'saiShare', 'mydoxShare', 'rateSource', 'payPeriod'
        ])
          if (fresh[k] != null) k: fresh[k],
        'urgent': fresh['urgent'] == true,
        'teamId': id,
        'status': 'open',
        'createdAt': IstClock.now().toIso8601String(),
      });
      try {
        final profile =
            (await _db.collection(collection).doc(uid).get()).data() ??
                const <String, dynamic>{};
        await claimShift(
          child.id,
          {...profile, 'uid': uid, 'name': profile['name'] ?? a['name']},
          viaAgencyId: agencyId,
        );
        ok.add(uid);
        names.add((profile['name'] ?? a['name'] ?? '').toString());
      } catch (e) {
        await child.delete();
        failed.add('${a['name']}: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (ok.isNotEmpty) {
      final total = done.length + ok.length;
      await ref.update({
        'allocatedUids': FieldValue.arrayUnion(ok),
        'allocatedNames': FieldValue.arrayUnion(names),
        if (total >= size) 'status': 'filled',
        if (total >= size) 'filledAt': IstClock.now().toIso8601String(),
      });
    }
    return failed;
  }

  static Future<void> cancelTeamRequest(String id) => _db
      .collection(teamCol)
      .doc(id)
      .update({'status': 'cancelled', 'cancelledAt': IstClock.now().toIso8601String()});

  /// The hospital's own team requests.
  static Stream<List<Map<String, dynamic>>> posterTeamRequestsStream(
          String posterId) =>
      _db
          .collection(teamCol)
          .where('posterId', isEqualTo: posterId)
          .snapshots()
          .map((s) => _teamsOf(s)
            ..sort((a, b) => (shiftStart(b) ?? DateTime(2000))
                .compareTo(shiftStart(a) ?? DateTime(2000))));

  /// Every hospital's team request (agencies pick from their own doctors).
  static Stream<List<Map<String, dynamic>>> hospitalTeamRequestsStream() =>
      _db
          .collection(teamCol)
          .where('postedBy', isEqualTo: 'hospital')
          .snapshots()
          .map((s) => _teamsOf(s)
            ..sort((a, b) => (shiftStart(a) ?? DateTime(2100))
                .compareTo(shiftStart(b) ?? DateTime(2100))));

  static Future<void> postTeamRequest({
    required String posterId,
    required String posterName,
    required String hospitalId,
    required String hospitalName,
    required String area,
    required String dutyType,
    String specialty = '',
    List<String> procedures = const [],
    required String date,
    required String slot,
    required String start,
    required String end,
    int pay = 0, // the hospital pays the master-table rate
    required int teamSize,
    bool urgent = false,
    bool rotation = false,
  }) async {
    await FirestoreService.assertRequesterVerified(posterId);
    final rate = await TechnicianDutyRates.load(dutyType);
    if (rate == null || rate.monthlySalary == null) {
      throw Exception(TechnicianDutyRates.notSetMessage);
    }
    pay = rate.monthlySalary!; // a full-time team is paid per month
    final s = shiftStart({'date': date, 'start': start, 'end': end});
    if (s == null || !s.isAfter(IstClock.now())) {
      throw Exception('Pick a shift that has not started yet.');
    }
    if (pay <= 0) throw Exception('Enter the pay per doctor.');
    if (teamSize < 2 || teamSize > 50) {
      throw Exception('A team is 2 to 50 technicians.');
    }
    if (rotation) {
      if (teamSize != 3) {
        throw Exception('A weekly rotation team is three technicians.');
      }
      final start = IstClock.tryParse(date);
      final today = IstClock.now();
      if (start == null ||
          !start.isAfter(DateTime(today.year, today.month, today.day))) {
        throw Exception('The rotation has to start after today.');
      }
    }
    await _db.collection(teamCol).add({
      'postedBy': 'hospital',
      'isTeam': true,
      'posterId': posterId,
      'posterName': posterName,
      'hospitalId': hospitalId,
      'hospitalName': hospitalName,
      'area': area,
      'dutyType': dutyType,
      'specialty': specialty,
      'procedures': const <String>[], // a full-time team has no procedure list
      'date': date,
      'slot': slot,
      'start': start,
      'end': end,
      'pay': pay,
      ...rate.toTeamFields(),
      'urgent': urgent,
      if (rotation) ...{'rotation': true, 'anchor': date},
      'teamSize': teamSize,
      'applicantUids': <String>[],
      'applicants': <String, dynamic>{},
      'allocatedUids': <String>[],
      'allocatedNames': <String>[],
      'status': 'open',
      'createdAt': IstClock.now().toIso8601String(),
    });
  }

  /// Duties the agency's own technicians took (freelancers are not
  /// included, and neither are patients' home visits).
  static Stream<List<Map<String, dynamic>>> agencyShiftsStream(String agencyId) =>
      _db
          .collection(shiftsCol)
          .where('claimedAgencyId', isEqualTo: agencyId)
          .snapshots()
          .map((s) => _withIds(s)..removeWhere((r) => r['postedBy'] == 'patient'));

  static Stream<List<Map<String, dynamic>>> activeJobsStream() => _db
      .collection(jobsCol)
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) => _withIds(s)
        ..sort((a, b) {
          final u = (b['urgent'] == true ? 1 : 0)
              .compareTo(a['urgent'] == true ? 1 : 0);
          if (u != 0) return u;
          return (b['createdAt'] ?? '')
              .toString()
              .compareTo((a['createdAt'] ?? '').toString());
        }));

  static Stream<List<Map<String, dynamic>>> posterShiftsStream(
          String posterId) =>
      _db
          .collection(shiftsCol)
          .where('posterId', isEqualTo: posterId)
          .snapshots()
          .map((s) => _withIds(s)
            ..sort((a, b) => (shiftStart(b) ?? DateTime(2000))
                .compareTo(shiftStart(a) ?? DateTime(2000))));

  /// Technician requests that hospitals posted: the only requests a
  /// partner agency sees. A patient's home visit (postedBy 'patient') is
  /// never part of it.
  static Stream<List<Map<String, dynamic>>> hospitalRequestsStream() => _db
      .collection(shiftsCol)
      .where('postedBy', isEqualTo: 'hospital')
      .snapshots()
      .map((s) => _withIds(s)
        ..removeWhere((r) => r['postedBy'] != 'hospital')
        ..sort((a, b) => (shiftStart(a) ?? DateTime(2100))
            .compareTo(shiftStart(b) ?? DateTime(2100))));

  static Stream<List<Map<String, dynamic>>> posterJobsStream(
          String posterId) =>
      _db
          .collection(jobsCol)
          .where('posterId', isEqualTo: posterId)
          .snapshots()
          .map((s) => _withIds(s)
            ..sort((a, b) => (b['createdAt'] ?? '')
                .toString()
                .compareTo((a['createdAt'] ?? '').toString())));

  static Stream<List<Map<String, dynamic>>> interestsStream(String jobId) =>
      _db
          .collection(jobsCol)
          .doc(jobId)
          .collection('interests')
          .snapshots()
          .map((s) => _withIds(s)
            ..sort((a, b) => (b['at'] ?? '')
                .toString()
                .compareTo((a['at'] ?? '').toString())));

  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection(collection).doc(uid).set(
          {...data, 'updatedAt': IstClock.now().toIso8601String()},
          SetOptions(merge: true));

  static Future<void> setAvailable(String uid, bool available) =>
      updateProfile(uid, {'available': available, 'isOnline': available});

  /// One record per doctor holding the times they are booked
  /// ({shiftId: {start, end, label}}). Read and written inside the claim
  /// transaction, so two claims at the same moment cannot both pass the
  /// overlap check.
  static DocumentReference<Map<String, dynamic>> scheduleRef(String uid) =>
      _db.collection('technician_schedules').doc(uid);

  /// Why [shift] clashes with the doctor's booked times (null = free).
  static String? scheduleClash(Map<String, dynamic>? schedule,
      Map<String, dynamic> shift, String shiftId, DateTime now) {
    final start = shiftStart(shift), end = shiftEnd(shift);
    if (start == null || end == null) return null;
    final slots = (schedule?['slots'] as Map?) ?? const {};
    for (final e in slots.entries) {
      if (e.key == shiftId || e.value is! Map) continue;
      final a = IstClock.tryParse('${e.value['start']}');
      final b = IstClock.tryParse('${e.value['end']}');
      if (a == null || b == null || !b.isAfter(now)) continue;
      if (a.isBefore(end) && start.isBefore(b)) {
        return 'You already have a shift at that time '
            '(${e.value['label'] ?? 'another shift'}).';
      }
    }
    return null;
  }

  /// First to confirm gets the shift. An agency's shift also becomes a duty
  /// in the agency's Control Room, under the doctor's roster record.
  ///
  /// [viaAgencyId]: a partner agency assigns one of its own doctors to a
  /// hospital's request; the duty is then the agency's, whoever the doctor is.
  ///
  /// A hospital's request accepted by a doctor who belongs to an agency is
  /// not allocated yet: it waits for the agency ('pending_agency', the time
  /// is held for the doctor) until [approveRequest] or [declineRequest].
  /// [approval] is that second step.
  static Future<void> claimShift(
      String shiftId, Map<String, dynamic> me,
      {String? viaAgencyId, bool approval = false}) async {
    final ref = _db.collection(shiftsCol).doc(shiftId);
    final uid = me['uid'].toString();
    final mine = await _db
        .collection(shiftsCol)
        .where('claimedBy', isEqualTo: uid)
        .get();
    final first = (await ref.get()).data();
    // the hospital rotation rosters this doctor works are busy time too
    final rosterBusy = await TechnicianDutyService.rosterBusy(uid);
    final agencyId = StaffingClaimAgency.select(
      assignedByAgency: viaAgencyId, shift: first ?? {}, provider: me);
    final usesMembership = (viaAgencyId ?? '').isEmpty &&
        (first?['agencyId'] ?? '').toString().isEmpty && agencyId.isNotEmpty;
    final agency = agencyId.isEmpty
        ? null
        : (await _db.collection('agencies').doc(agencyId).get()).data();
    // the agency's own record of this doctor (its screens and payouts use it)
    String? rosterId;
    if (agencyId.isNotEmpty) {
      final roster = await _db
          .collection('agency_doctors')
          .where('agencyId', isEqualTo: agencyId)
          .where('userUid', isEqualTo: uid)
          .limit(1)
          .get();
      rosterId = roster.docs.isEmpty ? null : roster.docs.first.id;
    }
    // an urgent agency shift is an emergency locum: billed with the hike
    final pricing = agencyId.isEmpty
        ? const PricingSettings()
        : await PricingService.load();

    await _db.runTransaction((tx) async {
      final shift = (await tx.get(ref)).data();
      final schedule = (await tx.get(scheduleRef(uid))).data();
      if (usesMembership) {
        final liveProvider = (await tx.get(_db.collection(collection).doc(uid))).data();
        final liveAgency = (await tx.get(_db.collection('agencies').doc(agencyId))).data();
        if (!StaffingClaimAgency.membershipValid(agencyId: agencyId,
            provider: liveProvider, agency: liveAgency, agencyType: 'technician')) {
          throw Exception('Your agency association changed or is inactive. Refresh your profile before claiming.');
        }
      }
      final status = shift?['status'];
      final approving = approval &&
          status == 'pending_agency' &&
          (shift?['claimedBy'] ?? '').toString() == uid;
      if (shift == null || (status != 'open' && !approving)) {
        throw Exception('Someone else just claimed this shift.');
      }
      final at = IstClock.now();
      final clash = rosterClashWith(shift, rosterBusy);
      if (clash != null) throw Exception(clash);
      final reason = claimBlockReason(
              shift,
              me,
              _withIds(mine).where((m) => m['id'] != shiftId).toList(),
              at) ??
          scheduleClash(schedule, shift, shiftId, at);
      if (reason != null) throw Exception(reason);

      final now = IstClock.now().toIso8601String();
      // no new request waits for its agency: the doctor is allocated at once
      // (an older pending one can still be approved or declined)
      final update = <String, dynamic>{
        if (approving) ...{
          'pendingAgencyId': FieldValue.delete(),
          'pendingAgencyName': FieldValue.delete(),
          'pendingAt': FieldValue.delete(),
          'approvedAt': now,
        },
        'status': 'claimed',
        'claimedBy': uid,
        'claimedByName': (me['name'] ?? '').toString(),
        'claimedByPhone': (me['phone'] ?? me['mobileNumber'] ?? '').toString(),
        'claimedAt': now,
      };
      // an agency doctor took it: the agency sees the visit and who accepted
      final myAgency =
          viaAgencyId ?? (me['agencyId'] ?? '').toString();
      if (myAgency.isNotEmpty) {
        update['claimedAgencyId'] = myAgency;
        update['claimedAgencyName'] = (me['agencyName'] ?? '').toString();
        update['agencyWatch'] = FieldValue.arrayUnion([myAgency]);
      }
      if (agencyId.isNotEmpty) {
        final pay = toNum(shift['pay']) ?? 0;
        // a shift priced from the master table keeps its own split
        // (physician pay, Sai Services and MyDox shares); any other shift
        // uses the agency's split
        final master = shift['rateSource'] == 'master';
        final rates = master
            ? {'baseRate': pay.round(), 'hospitalRate': pay.round()}
            : CareAgencyService.rateFields(
                shift['urgent'] == true ? 'emergency' : 'locum', pay, pricing);
        final split = master
            ? (
                doctorPay: (toNum(shift['doctorPay']) ?? 0).round(),
                agencyShare: (toNum(shift['saiShare']) ?? 0).round(),
                appShare: (toNum(shift['mydoxShare']) ?? 0).round(),
              )
            : CareAgencyService.split(
                rates['hospitalRate'] as num, agency ?? const {});
        final dutyRef = _db.collection('duties').doc();
        final type = shift['dutyType']?.toString();
        // not on this agency's roster yet: added as a locum, so the duty
        // and its payout show under this doctor in the Control Room
        final doctorId = rosterId ?? '${agencyId}_$uid';
        if (rosterId == null) {
          tx.set(
              _db.collection('agency_doctors').doc(doctorId),
              {
                'agencyId': agencyId,
                'name': update['claimedByName'],
                'phone': CareAgencyService.normalizePhone(
                    update['claimedByPhone'].toString()),
                'qualification': me['qualification'] ?? '',
                'regNo': me['regNo'] ?? '',
                'placementType': 'locum',
                'active': true,
                'userUid': uid,
                'joinedBy': 'shift',
                'createdAt': now,
              },
              SetOptions(merge: true));
        }
        tx.set(dutyRef, {
          'agencyId': agencyId,
          'doctorId': doctorId,
          'doctorUserUid': uid,
          'doctorName': update['claimedByName'],
          'hospitalId': shift['hospitalId'] ?? '',
          'hospitalName': shift['hospitalName'] ?? '',
          'type': shift['urgent'] == true ? 'emergency' : 'locum',
          'dutyType': type, // ward, icu or specialty (for the earnings lists)
          'unit': const {'icu': 'icu', 'casualty': 'casualty'}[type] ??
              (shift['slot'] == 'night' ? 'night' : 'ward'),
          'date': shift['date'],
          'shiftStart': timestampOf(shiftStart(shift)!),
          'shiftEnd': timestampOf(shiftEnd(shift)!),
          'status': 'scheduled',
          ...rates,
          'doctorPay': split.doctorPay,
          'agencyShare': split.agencyShare,
          'appShare': split.appShare,
          'payoutStatus': 'due',
          'shiftId': shiftId,
          'createdAt': now,
        });
        update['dutyId'] = dutyRef.id;
        // what the doctor actually earns after the agency's split
        update['doctorPay'] = split.doctorPay;
      }
      tx.update(ref, update);
      tx.set(
          scheduleRef(uid),
          {
            'slots': {
              shiftId: {
                'start': shiftStart(shift)!.toIso8601String(),
                'end': shiftEnd(shift)!.toIso8601String(),
                'label':
                    '${shift['hospitalName'] ?? 'Shift'}, ${timeRange(shift)}',
              },
            },
          },
          SetOptions(merge: true));
    });
  }

  /// The agency approves its doctor for a hospital's request: the doctor is
  /// now allocated to the hospital (it becomes the agency's duty).
  static Future<void> approveRequest(
      Map<String, dynamic> shift, String agencyId) async {
    final uid = (shift['claimedBy'] ?? '').toString();
    if (uid.isEmpty || shift['pendingAgencyId'] != agencyId) {
      throw Exception('This request is not waiting for your approval.');
    }
    final profile = (await _db.collection(collection).doc(uid).get()).data() ??
        const <String, dynamic>{};
    await claimShift(
      shift['id'].toString(),
      {
        ...profile,
        'uid': uid,
        'name': profile['name'] ?? shift['claimedByName'],
        'phone': profile['phone'] ?? shift['claimedByPhone'],
      },
      viaAgencyId: agencyId,
      approval: true,
    );
  }

  /// The agency does not send this doctor: the request opens again for
  /// other technicians and the doctor's time is freed.
  static Future<void> declineRequest(
      Map<String, dynamic> shift, String agencyId) async {
    final id = shift['id'].toString();
    final ref = _db.collection(shiftsCol).doc(id);
    await _db.runTransaction((tx) async {
      final fresh = (await tx.get(ref)).data();
      if (fresh == null ||
          fresh['status'] != 'pending_agency' ||
          fresh['pendingAgencyId'] != agencyId) {
        throw Exception('This request is no longer waiting for approval.');
      }
      final doctor = (fresh['claimedBy'] ?? '').toString();
      final schedule = await tx.get(scheduleRef(doctor));
      tx.update(ref, {
        'status': 'open',
        'declinedBy': FieldValue.arrayUnion([doctor]),
        'declinedByAgencyAt': IstClock.now().toIso8601String(),
        'claimedBy': FieldValue.delete(),
        'claimedByName': FieldValue.delete(),
        'claimedByPhone': FieldValue.delete(),
        'pendingAgencyId': FieldValue.delete(),
        'pendingAgencyName': FieldValue.delete(),
        'pendingAt': FieldValue.delete(),
      });
      if (schedule.exists) {
        tx.update(schedule.reference, {'slots.$id': FieldValue.delete()});
      }
    });
  }

  /// Why [shift] overlaps a duty on a hospital rotation roster (null = free).
  static String? rosterClashWith(
      Map<String, dynamic> shift, List<BusyInterval> busy) {
    final a = IstClock.maybeToInstant(shiftStart(shift)),
        b = IstClock.maybeToInstant(shiftEnd(shift));
    if (a == null || b == null) return null;
    for (final x in busy) {
      if (a.isBefore(x.end) && x.start.isBefore(b)) {
        return 'You are on the duty roster${x.label.isEmpty ? '' : ' at ${x.label}'} at that time.';
      }
    }
    return null;
  }

  /// The same check for the screen, before the doctor confirms.
  static Future<String?> rosterClash(
          Map<String, dynamic> shift, String uid) async =>
      rosterClashWith(shift, await TechnicianDutyService.rosterBusy(uid));

  // ------------------------------------------------------- arrival OTP

  /// A hospital's locum is started with an OTP: the technician gets one
  /// when he arrives, the hospital enters it, and he has to be within
  /// [arrivalRadiusMeters] of the hospital at that moment.
  static const double arrivalRadiusMeters = 500;
  static const Duration arrivalOtpValid = Duration(minutes: 10);

  static bool usesArrivalOtp(Map<String, dynamic> s) =>
      s['postedBy'] == 'hospital';

  /// The OTP that is still valid for [s], or null.
  static String? activeArrivalOtp(Map<String, dynamic> s, DateTime now) {
    final otp = (s['arrivalOtp'] ?? '').toString();
    final at = IstClock.tryParse((s['arrivalOtpAt'] ?? '').toString());
    if (otp.isEmpty || at == null || s['status'] != 'claimed') return null;
    return now.difference(at) < arrivalOtpValid ? otp : null;
  }

  /// The doctor's live position, taken now and only for the OTP.
  static Future<Position> _livePositionNow() async {
    if (!await LabLocation.isLocationServiceEnabled()) {
      throw Exception('Turn on location (GPS) to get the arrival OTP.');
    }
    var permission = await LabLocation.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await LabLocation.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Allow location access to get the arrival OTP.');
    }
    try {
      return await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw Exception('Could not read your location. Move near a window and try again.');
    }
  }

  /// Technician: arrived. Reads the live location once and issues the OTP.
  static Future<String> generateArrivalOtp(Map<String, dynamic> shift) async {
    final ref = _db.collection(shiftsCol).doc(shift['id'].toString());
    final fresh = (await ref.get()).data();
    if (fresh == null || !canCheckIn(fresh, IstClock.now())) {
      throw Exception(
          'The arrival OTP opens 1 hour before your shift and closes when it ends.');
    }
    final pos = await _livePositionNow();
    final otp = ServiceOtp.generate();
    await ref.update({
      'arrivalOtp': otp,
      'arrivalOtpAt': IstClock.now().toIso8601String(),
      'arrivalLat': pos.latitude,
      'arrivalLng': pos.longitude,
      'arrivalAccuracyM': pos.accuracy.round(),
    });
    return otp;
  }

  /// Hospital: enters the OTP the technician shows. The physician must be
  /// within 500 m of the hospital (his position at the moment of the OTP).
  /// Returns the minutes he is late (0 = on time).
  static Future<int> verifyArrival(
      Map<String, dynamic> shift, String enteredOtp, String hospitalUid) async {
    final ref = _db.collection(shiftsCol).doc(shift['id'].toString());
    final hospital =
        (await _db.collection('hospitals').doc(hospitalUid).get()).data();
    final hLat = (hospital?['latitude'] as num?)?.toDouble();
    final hLng = (hospital?['longitude'] as num?)?.toDouble();
    if (hLat == null || hLng == null) {
      throw Exception(
          'Your hospital location is not set. Set it in your profile first.');
    }
    final late = await _db.runTransaction<int>((tx) async {
      final s = (await tx.get(ref)).data();
      final now = IstClock.now();
      if (s == null || s['posterId'] != hospitalUid) {
        throw Exception('This is not your shift.');
      }
      if (s['status'] != 'claimed') {
        throw Exception('This shift is not waiting for arrival.');
      }
      final otp = activeArrivalOtp(s, now);
      if (otp == null) {
        throw Exception(
            'No valid OTP. Ask the technician to get a new one (valid 10 minutes).');
      }
      if (otp != enteredOtp.trim()) throw Exception('Wrong OTP.');
      final lat = toNum(s['arrivalLat'])?.toDouble();
      final lng = toNum(s['arrivalLng'])?.toDouble();
      if (lat == null || lng == null) {
        throw Exception('The technician location was not captured. Get a new OTP.');
      }
      final meters = SosService.distanceKm(lat, lng, hLat, hLng) * 1000;
      if (meters > arrivalRadiusMeters) {
        throw Exception(
            'The technician is about ${meters.round()} m from the hospital. '
            'He must be within ${arrivalRadiusMeters.round()} m to start.');
      }
      final mins = now.difference(shiftStart(s)!).inMinutes;
      final late = mins > lateAfterMinutes ? mins : 0;
      tx.update(ref, {
        'status': 'on_duty',
        'checkInAt': now.toIso8601String(),
        'lateMinutes': late,
        'arrivalVerifiedBy': hospitalUid,
        'arrivalDistanceM': meters.round(),
        'arrivalOtp': FieldValue.delete(),
      });
      return late;
    });
    final dutyId = (shift['dutyId'] ?? '').toString();
    if (dutyId.isNotEmpty) {
      try {
        await CareAgencyService.checkIn(dutyId);
      } catch (_) {}
    }
    return late;
  }

  static Future<int> checkIn(Map<String, dynamic> shift) async {
    final ref = _db.collection(shiftsCol).doc(shift['id'].toString());
    final late = await _db.runTransaction<int>((tx) async {
      final s = (await tx.get(ref)).data();
      final now = IstClock.now();
      if (s == null || !canCheckIn(s, now)) {
        throw Exception(
            'Check-in is open from 1 hour before your shift until it ends.');
      }
      if (usesArrivalOtp(s)) {
        throw Exception('Get the arrival OTP and show it to the hospital.');
      }
      final mins = now.difference(shiftStart(s)!).inMinutes;
      final late = mins > lateAfterMinutes ? mins : 0;
      tx.update(ref, {
        'status': 'on_duty',
        'checkInAt': now.toIso8601String(),
        'lateMinutes': late,
      });
      return late;
    });
    final dutyId = (shift['dutyId'] ?? '').toString();
    if (dutyId.isNotEmpty) {
      try {
        await CareAgencyService.checkIn(dutyId);
      } catch (_) {
        // the shift is checked in; the agency sees it on the next refresh
      }
    }
    return late;
  }

  static Future<void> checkOut(Map<String, dynamic> shift) async {
    final ref = _db.collection(shiftsCol).doc(shift['id'].toString());
    await _db.runTransaction((tx) async {
      final s = (await tx.get(ref)).data();
      if (s == null || !canCheckOut(s)) {
        throw Exception('Check in first, then check out at the end.');
      }
      tx.update(ref, {
        'status': 'completed',
        'checkOutAt': IstClock.now().toIso8601String(),
      });
    });
    final dutyId = (shift['dutyId'] ?? '').toString();
    if (dutyId.isNotEmpty) {
      try {
        await CareAgencyService.checkOut(dutyId);
      } catch (_) {}
    }
  }

  /// Claimed shifts never checked in 4 h after the start become 'absent'
  /// and count as a no-show for the technician.
  static Future<void> markNoShows(
      List<Map<String, dynamic>> shifts, DateTime now) async {
    for (final s in shifts.where((s) => isNoShow(s, now))) {
      final ref = _db.collection(shiftsCol).doc(s['id'].toString());
      try {
        await _db.runTransaction((tx) async {
          final cur = (await tx.get(ref)).data();
          if (cur == null || !isNoShow(cur, now)) return;
          tx.update(ref, {'status': 'absent', 'absentAt': now.toIso8601String()});
          final who = (cur['claimedBy'] ?? '').toString();
          if (who.isNotEmpty) {
            tx.set(_db.collection(collection).doc(who),
                {'noShows': FieldValue.increment(1)}, SetOptions(merge: true));
          }
        });
      } catch (_) {
        // someone else marked it first
      }
    }
  }

  /// Express interest in a full-time job; the poster sees the profile.
  /// The doctor turns down a patient's home visit: it leaves their list and
  /// stays open for the other doctors.
  static Future<void> declineShift(String shiftId, String uid) =>
      _db.collection(shiftsCol).doc(shiftId).update({
        'declinedBy': FieldValue.arrayUnion([uid]),
      });

  static Future<void> expressInterest(
      String jobId, Map<String, dynamic> me) async {
    if (!isVerified(me)) {
      throw Exception('Your registration is pending verification.');
    }
    final uid = me['uid'].toString();
    final job = _db.collection(jobsCol).doc(jobId);
    final batch = _db.batch();
    batch.set(job.collection('interests').doc(uid), {
      'uid': uid,
      'name': me['name'] ?? '',
      'phone': me['phone'] ?? me['mobileNumber'] ?? '',
      'qualification': me['qualification'] ?? '',
      'experienceYears': me['experienceYears'] ?? 0,
      'regNo': me['regNo'] ?? '',
      'verified': isVerified(me),
      'status': 'new',
      'at': IstClock.now().toIso8601String(),
    });
    batch.update(job, {
      'interestedUids': FieldValue.arrayUnion([uid]),
    });
    await batch.commit();
  }

  // ------------------------------------------------------------ posting

  /// Hospital, agency or admin posts a shift (status 'open').
  static Future<void> postShift({
    required String postedBy, // 'hospital' | 'agency' | 'admin'
    required String posterId,
    required String posterName,
    String? agencyId,
    required String hospitalId,
    required String hospitalName,
    required String area,
    required String dutyType,
    String specialty = '',
    List<String> procedures = const [],
    required String date,
    required String slot,
    required String start,
    required String end,
    int pay = 0, // not used for a hospital: it pays the master-table rate
    bool urgent = false,
  }) async {
    TechnicianDutyRate? rate;
    if (postedBy == 'hospital') {
      await FirestoreService.assertRequesterVerified(posterId);
      rate = await TechnicianDutyRates.load(dutyType);
      if (rate == null) throw Exception(TechnicianDutyRates.notSetMessage);
      pay = rate.hospitalRate;
    }
    final draft = {'date': date, 'start': start, 'end': end};
    final s = shiftStart(draft);
    if (s == null || !s.isAfter(IstClock.now())) {
      throw Exception('Pick a shift that has not started yet.');
    }
    if (pay <= 0) throw Exception('Enter the pay for this shift.');
    // an agency's shift: the doctor sees their share, not the full rate
    int? doctorPay;
    if (agencyId != null && agencyId.isNotEmpty) {
      final agency =
          (await _db.collection('agencies').doc(agencyId).get()).data();
      final billed = (await PricingService.load())
          .billedRate(urgent ? 'emergency' : 'locum', pay);
      doctorPay =
          CareAgencyService.split(billed, agency ?? const {}).doctorPay;
    }
    await _db.collection(shiftsCol).add({
      'postedBy': postedBy,
      'posterId': posterId,
      'posterName': posterName,
      if (agencyId != null && agencyId.isNotEmpty) 'agencyId': agencyId,
      'hospitalId': hospitalId,
      'hospitalName': hospitalName,
      'area': area,
      'dutyType': dutyType,
      'specialty': specialty,
      'procedures': procedures,
      'date': date,
      'slot': slot,
      'start': start,
      'end': end,
      'pay': pay,
      if (doctorPay != null) 'doctorPay': doctorPay,
      // a hospital's price, the technician's pay and the shares
      if (rate != null) ...rate.toShiftFields(),
      'urgent': urgent,
      // a hospital's shift: agency technicians first, everyone after 5 min
      if (postedBy == 'hospital') ...{
        'agencyFirst': true,
        'agencyOfferUntil':
            IstClock.now().add(hospitalAgencyFirst).toIso8601String(),
      },
      'status': 'open',
      'createdAt': IstClock.now().toIso8601String(),
    });
  }

  /// Poster cancels an open shift (a claimed one also frees the doctor and
  /// cancels the agency duty).
  /// Cancels the shift as it is now, not as the screen last saw it: its
  /// current duty is cancelled and the doctor's time is freed, together.
  static Future<void> cancelShift(Map<String, dynamic> shift) async {
    final id = shift['id'].toString();
    final ref = _db.collection(shiftsCol).doc(id);
    await _db.runTransaction((tx) async {
      final fresh = (await tx.get(ref)).data();
      if (fresh == null) return;
      final doctor = (fresh['claimedBy'] ?? '').toString();
      final schedule =
          doctor.isEmpty ? null : await tx.get(scheduleRef(doctor));
      tx.update(ref, {
        'status': 'cancelled',
        'cancelledAt': IstClock.now().toIso8601String(),
      });
      final dutyId = (fresh['dutyId'] ?? '').toString();
      if (dutyId.isNotEmpty) {
        tx.update(
            _db.collection('duties').doc(dutyId), {'status': 'cancelled'});
      }
      if (schedule != null && schedule.exists) {
        tx.update(schedule.reference, {'slots.$id': FieldValue.delete()});
      }
    });
  }

  static Future<void> postJob({
    String? id,
    required String postedBy,
    required String posterId,
    required String posterName,
    required String hospitalId,
    required String hospitalName,
    required String area,
    required String title,
    required String unit,
    required String dutyType,
    required String timing,
    String timingNote = '',
    required int salaryMin,
    required int salaryMax,
    required int openings,
    List<String> qualifications = const [],
    List<String> procedures = const [],
    String benefits = '',
    bool urgent = false,
    bool active = true,
  }) async {
    if (salaryMax > 0 && salaryMin > salaryMax) {
      throw Exception('Minimum salary is more than the maximum.');
    }
    final data = {
      'postedBy': postedBy,
      'posterId': posterId,
      'posterName': posterName,
      'hospitalId': hospitalId,
      'hospitalName': hospitalName,
      'area': area,
      'title': title,
      'unit': unit,
      'dutyType': dutyType,
      'timing': timing,
      'timingNote': timingNote,
      'salaryMin': salaryMin,
      'salaryMax': salaryMax,
      'openings': openings,
      'qualifications': qualifications,
      'procedures': procedures,
      'benefits': benefits,
      'urgent': urgent,
      'active': active,
      'updatedAt': IstClock.now().toIso8601String(),
    };
    if (id == null) {
      await _db.collection(jobsCol).add({
        ...data,
        'interestedUids': <String>[],
        'createdAt': IstClock.now().toIso8601String(),
      });
    } else {
      await _db
          .collection(jobsCol)
          .doc(id)
          .set(data, SetOptions(merge: true));
    }
  }

  static Future<void> setJobActive(String id, bool active) => _db
      .collection(jobsCol)
      .doc(id)
      .set({'active': active}, SetOptions(merge: true));

  // -------------------------------------------------- patient home visits

  /// Home-visit services a patient books (Firestore
  /// `care_physician_services`, live): name, price ("onwards"), icon,
  /// description, procedures (keys of [procedures]), isActive, order.
  static const String servicesCol = 'care_physician_services';

  static List<Map<String, dynamic>> servicesOf(
      QuerySnapshot<Map<String, dynamic>> s) {
    final list = [
      for (final d in s.docs)
        if (d.data()['isActive'] != false &&
            (d.data()['name'] ?? '').toString().trim().isNotEmpty)
          {...d.data(), 'id': d.id}
    ];
    list.sort((a, b) {
      final o = (toNum(a['order']) ?? 999)
          .compareTo(toNum(b['order']) ?? 999);
      return o != 0
          ? o
          : a['name'].toString().compareTo(b['name'].toString());
    });
    return list;
  }

  static Stream<List<Map<String, dynamic>>> servicesStream() =>
      _db.collection(servicesCol).snapshots().map(servicesOf);

  /// Home-visit time slots a patient can pick (start times).
  static List<String> visitTimes() => [
        for (var h = 8; h <= 20; h++) '${h.toString().padLeft(2, '0')}:00',
      ];

  static bool isHomeVisit(Map<String, dynamic> s) => s['postedBy'] == 'patient';

  /// A patient books a technician home visit: posted like a shift
  /// (duty type 'home') to technicians who do home visits in the area;
  /// the first to claim it comes.
  static Future<void> bookHomeVisit({
    required Map<String, dynamic> patient,
    required Map<String, dynamic> service,
    required String date,
    required String start,
    required String area,
    required String address,
    String notes = '',
    double? lat,
    double? lng,
  }) async {
    final h = int.parse(start.split(':')[0]);
    final end = '${((h + 1) % 24).toString().padLeft(2, '0')}:${start.split(':')[1]}';
    final draft = {'date': date, 'start': start, 'end': end};
    final s = shiftStart(draft);
    if (s == null || !s.isAfter(IstClock.now())) {
      throw Exception('Pick a time later than now.');
    }
    final price = toNum(service['price'])?.round() ?? 0;
    if (price <= 0) throw Exception('This service has no price yet.');
    // agencies with doctors in this area get it first for 15 min
    final firstAgencies = await agenciesFirstFor(area);
    await _db.collection(shiftsCol).add({
      'postedBy': 'patient',
      'posterId': patient['uid'],
      'posterName': patient['name'] ?? 'Patient',
      'patientPhone': patient['phone'] ?? patient['mobileNumber'] ?? '',
      'serviceId': service['id'],
      'serviceName': service['name'],
      'serviceIcon': service['icon'] ?? '',
      // the card title on the technician's side
      'hospitalName': service['name'],
      'hospitalId': '',
      'area': area,
      'address': address,
      'notes': notes,
      if (lat != null) 'patientLat': lat,
      if (lng != null) 'patientLng': lng,
      'offerAgencyIds': firstAgencies,
      'agencyWatch': firstAgencies,
      if (firstAgencies.isNotEmpty)
        'agencyOfferUntil':
            IstClock.now().add(agencyFirstWindow).toIso8601String(),
      'dutyType': 'home',
      'specialty': '',
      'procedures': listOf(service['procedures']),
      'date': date,
      'slot': 'visit',
      'start': start,
      'end': end,
      'pay': price,
      'urgent': false,
      'status': 'open',
      'createdAt': IstClock.now().toIso8601String(),
    });
  }

  // ------------------------------------------------------------ agencies

  /// How long agency technicians get a hospital's shift before it opens
  /// to technicians without an agency.
  static const Duration hospitalAgencyFirst = Duration(minutes: 5);

  /// How long an agency's doctors get a patient's home visit first.
  static const Duration agencyFirstWindow = Duration(minutes: 15);

  /// Technician agencies (to join at registration or from the profile).
  static Stream<List<Map<String, dynamic>>> careAgenciesStream() => _db
      .collection('agencies')
      .where('agencyType', isEqualTo: 'technician')
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              if (d.data()['active'] != false) {...d.data(), 'id': d.id}
          ]..sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase())));

  /// The technician joins a technician agency: they appear in the
  /// agency's Doctors list straight away (no approval) and get its patients'
  /// home visits first.
  static Future<void> joinAgency(
      Map<String, dynamic> me, String agencyId, String agencyName) async {
    final uid = me['uid'].toString();
    final previous = (me['agencyId'] ?? '').toString();
    final batch = _db.batch();
    if (previous.isNotEmpty && previous != agencyId) {
      batch.set(_db.collection('agency_doctors').doc('${previous}_$uid'),
          {'active': false, 'leftAt': IstClock.now().toIso8601String()},
          SetOptions(merge: true));
    }
    batch.set(_db.collection('agency_doctors').doc('${agencyId}_$uid'), {
      'agencyId': agencyId,
      'name': me['name'] ?? '',
      'phone': CareAgencyService.normalizePhone(
          (me['phone'] ?? me['mobileNumber'] ?? '').toString()),
      'qualification': me['qualification'] ?? '',
      'regNo': me['regNo'] ?? '',
      'placementType': 'pool',
      'active': true,
      'userUid': uid,
      'joinedBy': 'doctor',
      'createdAt': IstClock.now().toIso8601String(),
    }, SetOptions(merge: true));
    batch.set(
        _db.collection(collection).doc(uid),
        {'agencyId': agencyId, 'agencyName': agencyName},
        SetOptions(merge: true));
    await batch.commit();
  }

  /// Leaves the agency and works as a freelancer (profile and history kept).
  static Future<void> leaveAgency(Map<String, dynamic> me) async {
    final uid = me['uid'].toString();
    final agencyId = (me['agencyId'] ?? '').toString();
    final batch = _db.batch();
    if (agencyId.isNotEmpty) {
      batch.set(_db.collection('agency_doctors').doc('${agencyId}_$uid'),
          {'active': false, 'leftAt': IstClock.now().toIso8601String()},
          SetOptions(merge: true));
    }
    batch.set(
        _db.collection(collection).doc(uid),
        {'agencyId': FieldValue.delete(), 'agencyName': FieldValue.delete()},
        SetOptions(merge: true));
    await batch.commit();
  }

  /// An agency added this doctor (by mobile number) in its Control Room:
  /// show the agency on the technician's profile too.
  static Future<void> syncAgencyFromRecords(Map<String, dynamic> me) async {
    if ((me['agencyId'] ?? '').toString().isNotEmpty) return;
    final ids = await CareAgencyService.linkDoctorRecords(
        me['uid'].toString(),
        (me['phone'] ?? me['mobileNumber'] ?? '').toString());
    for (final id in ids) {
      final rec = (await _db.collection('agency_doctors').doc(id).get()).data();
      if (rec == null || rec['active'] == false) continue;
      final agencyId = (rec['agencyId'] ?? '').toString();
      final agency = (await _db.collection('agencies').doc(agencyId).get()).data();
      if (agency == null) continue;
      await updateProfile(me['uid'].toString(),
          {'agencyId': agencyId, 'agencyName': agency['name'] ?? ''});
      return;
    }
  }

  /// Agencies whose available home-visit doctors serve [location]: they get
  /// the patient's visit first.
  static Future<List<String>> agenciesFirstFor(String location) async {
    try {
      final agencies = await _db
          .collection('agencies')
          .where('agencyType', isEqualTo: 'technician')
          .get();
      final serving = [
        for (final a in agencies.docs)
          if (a.data()['active'] != false &&
              FirestoreService.providerServesArea(
                  listOf(a.data()['areas']), location))
            a.id
      ];
      if (serving.isEmpty) return const [];
      final doctors = await _db
          .collection(collection)
          .where('agencyId', whereIn: serving.take(30).toList())
          .get();
      final withDoctors = <String>{};
      for (final d in doctors.docs) {
        final p = d.data();
        final types = listOf(p['dutyTypes']);
        if (p['available'] != false &&
            (types.isEmpty || types.contains('home')) &&
            inMyAreas(listOf(p['areas']), location)) {
          withDoctors.add((p['agencyId'] ?? '').toString());
        }
      }
      return withDoctors.toList();
    } catch (_) {
      return const []; // no agency step: everyone in the area gets it
    }
  }

  /// Admin verifies a technician's registration (unlocks gated duties).
  static Future<void> setVerified(String uid, bool verified) =>
      updateProfile(uid, {'isVerified': verified});
}
