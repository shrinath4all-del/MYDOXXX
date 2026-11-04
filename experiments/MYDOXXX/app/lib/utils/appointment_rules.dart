import '../services/firestore_service.dart';

/// How appointments are grouped and ordered in the doctor and patient lists.
class AppointmentRules {
  AppointmentRules._();

  static const String sosType = 'SOS Emergency Pipeline';

  static const Set<String> finishedStatuses = {
    'Completed',
    'Declined',
    'Provider Absent',
    'Cancelled',
    'Expired', // ran out of time after a hospital / doctor had accepted
  };

  static String statusOf(Map<String, dynamic> a) =>
      (a['status'] ?? 'Confirmed').toString();

  static bool isFinished(Map<String, dynamic> a) =>
      finishedStatuses.contains(statusOf(a));

  static bool isSos(Map<String, dynamic> a) => a['consultationType'] == sosType;

  /// Urgent doctor request (not SOS).
  static bool isUrgent(Map<String, dynamic> a) =>
      !isSos(a) &&
      (a['isUrgentEmergency'] == true ||
          (a['time'] ?? '').toString().toUpperCase().contains('ASAP'));

  /// A normal "Book for later" appointment with a date and a time slot.
  static bool isScheduled(Map<String, dynamic> a) => !isSos(a) && !isUrgent(a);

  /// Start / end of the booked slot ("08:00 PM - 09:00 PM").
  static DateTime? start(Map<String, dynamic> a) =>
      FirestoreService.expectedArrival(a);
  static DateTime? end(Map<String, dynamic> a) => FirestoreService.sessionEnd(a);

  /// Upcoming list rule:
  ///  - not finished, and
  ///  - urgent / SOS requests stay while they are active, and
  ///  - scheduled appointments only for today and tomorrow, and only while the
  ///    slot has not ended yet (a slot that is running now still counts).
  static bool isUpcoming(Map<String, dynamic> a, {DateTime? now}) {
    now ??= DateTime.now();
    if (isFinished(a)) return false;
    if (!isScheduled(a)) return true;

    final s = start(a);
    final e = end(a);
    if (s == null) return true;

    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(s.year, s.month, s.day);
    final daysAhead = day.difference(today).inDays;
    final running = statusOf(a) == 'In Progress';
    if (daysAhead < 0 || daysAhead > 1) return running;
    if (running) return true;
    return e == null || e.isAfter(now);
  }

  /// A scheduled appointment after tomorrow: not in the Upcoming list yet,
  /// and not history either (it is still to come; see the calendar).
  static bool isLater(Map<String, dynamic> a, {DateTime? now}) {
    now ??= DateTime.now();
    if (isFinished(a) || !isScheduled(a)) return false;
    final s = start(a);
    if (s == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(s.year, s.month, s.day).difference(today).inDays > 1;
  }

  /// A booked slot that passed without the consultation ever starting.
  static bool isMissed(Map<String, dynamic> a, {DateTime? now}) =>
      !isFinished(a) && !isUpcoming(a, now: now) && !isLater(a, now: now);

  /// Completed / history list: finished or missed (never a future booking).
  static bool isHistory(Map<String, dynamic> a, {DateTime? now}) =>
      isFinished(a) || isMissed(a, now: now);

  /// The consultation has begun (OTP verified) or is already completed.
  static bool consultationStarted(Map<String, dynamic> a) {
    final s = statusOf(a);
    return s == 'In Progress' ||
        s == 'Completed' ||
        (a['startedAt'] ?? '').toString().isNotEmpty;
  }

  /// How long chat stays open after the consultation.
  static const Duration chatWindow = Duration(hours: 24);

  /// Chat opens when the consultation starts and stays open until 24 hours
  /// after it completed; before the start and after that it is closed.
  static ChatState chatState(Map<String, dynamic> a, {DateTime? now}) {
    now ??= DateTime.now();
    // chat opens when the consultation ENDS (not while it is running)
    if (statusOf(a) != 'Completed') return ChatState.notStarted;
    final done = DateTime.tryParse((a['completedAt'] ?? '').toString()) ??
        end(a) ??
        start(a);
    if (done == null) return ChatState.expired;
    return now.difference(done) < chatWindow
        ? ChatState.open
        : ChatState.expired;
  }

  static bool chatOpen(Map<String, dynamic> a, {DateTime? now}) =>
      chatState(a, now: now) == ChatState.open;

  /// "Clinic/Visit" is stored; patients read "Clinic Visit".
  static String modeLabel(Object? mode) =>
      (mode ?? 'Clinic Visit').toString().replaceAll('Clinic/Visit', 'Clinic Visit');

  /// Earliest first: a 10-11 appointment comes before a 12-1 one.
  static int compareByStart(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sa = start(a);
    final sb = start(b);
    if (sa == null && sb == null) return 0;
    if (sa == null) return 1;
    if (sb == null) return -1;
    return sa.compareTo(sb);
  }

  /// Newest first (for the completed list).
  static int compareByStartDesc(Map<String, dynamic> a, Map<String, dynamic> b) =>
      -compareByStart(a, b);

  /// Calendar filter group: 'sos', 'urgent', 'completed' or 'pending'.
  static String category(Map<String, dynamic> a) {
    if (isSos(a)) return 'sos';
    if (isUrgent(a)) return 'urgent';
    return statusOf(a) == 'Completed' ? 'completed' : 'pending';
  }

  /// Calendar date (YYYY-MM-DD) of an appointment.
  static String dateKey(Map<String, dynamic> a) {
    final raw = (a['date'] ?? '').toString();
    final key = FirestoreService.normalizeDateKey(raw);
    if (key.isNotEmpty) return key;
    final created = DateTime.tryParse((a['createdAt'] ?? '').toString());
    if (created == null) return '';
    return '${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}';
  }

  static String hm(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Whether the video call of a booking may run right now. A call can start
  /// at any time inside the booked slot (07:00-08:00 PM: anytime from 7 to 8),
  /// never before the slot starts, and ends by itself when the slot ends.
  /// [end] is when the call must end (null: no limit known).
  static ({bool open, String message, DateTime? end}) videoWindow(
      Map<String, dynamic> a,
      {DateTime? now}) {
    now ??= DateTime.now();
    if (!isScheduled(a)) {
      return (open: true, message: '', end: end(a));
    }
    final s = start(a);
    final e = end(a);
    if (s == null || e == null) return (open: true, message: '', end: null);
    if (now.isBefore(s)) {
      return (
        open: false,
        message:
            'The video consultation starts at ${hm(s)}. You can join any time between ${hm(s)} and ${hm(e)}.',
        end: e,
      );
    }
    if (!now.isBefore(e)) {
      return (
        open: false,
        message: 'This slot ended at ${hm(e)}, so the video call is closed.',
        end: e,
      );
    }
    return (open: true, message: '', end: e);
  }
}

/// Whether the patient and provider can chat about a booking.
enum ChatState { notStarted, open, expired }
