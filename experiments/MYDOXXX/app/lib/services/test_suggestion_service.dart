import 'app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_access_service.dart';

/// What happened when the patient chose "Book later".
enum LaterResult {
  /// A reminder is set for [TestSuggestionService.nextReminderAt].
  scheduled,

  /// The last reminder was used up: show the other options once and stop.
  showOtherOptions,
}

/// A doctor's advice to get a test done (MRI, blood test...), kept until the
/// patient books it. Stored in `test_suggestions/{id}`:
///
///   patientUid, patientName, doctorUid, doctorName, chatId
///   testName   a name from `lab_tests`
///   note       the doctor's note (may be empty)
///   status     suggested | later | booked | closed
///   laterCount how many times the patient chose "Book later"
///   remindAt   when to remind next (ISO time), while status is `later`
///   createdAt, bookedAt, appointmentId
///
/// Reminders: the first "Book later" reminds the next day, then every 2 days,
/// up to 3 reminders. After the last one the other options are shown once.
class TestSuggestionService {
  TestSuggestionService._();

  static const String collection = 'test_suggestions';

  /// Days until the next reminder after the 1st, 2nd and 3rd "Book later".
  static const List<int> reminderGapDays = [1, 2, 2];

  /// A suggestion the patient never answered gets its first reminder after
  /// this long.
  static const Duration unansweredAfter = Duration(days: 1);

  static FirebaseFirestore get _db => AppDatabase.instance;

  // ----------------------------------------------------------- schedule

  /// What "Book later" does for a suggestion that has been postponed
  /// [laterCountBefore] times already.
  static ({LaterResult result, DateTime? remindAt}) onBookLater(
      int laterCountBefore,
      {DateTime? now}) {
    now ??= DateTime.now();
    final next = laterCountBefore + 1;
    if (next > reminderGapDays.length) {
      return (result: LaterResult.showOtherOptions, remindAt: null);
    }
    return (
      result: LaterResult.scheduled,
      remindAt: now.add(Duration(days: reminderGapDays[next - 1])),
    );
  }

  /// Whether the patient should be reminded of [s] now.
  static bool isDue(Map<String, dynamic> s, {DateTime? now}) {
    now ??= DateTime.now();
    final status = (s['status'] ?? '').toString();
    if (status == 'later') {
      final at = DateTime.tryParse((s['remindAt'] ?? '').toString());
      return at != null && !at.isAfter(now);
    }
    if (status == 'suggested') {
      final made = DateTime.tryParse((s['createdAt'] ?? '').toString());
      return made != null && !made.add(unansweredAfter).isAfter(now);
    }
    return false;
  }

  static bool isOpen(Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString();
    return status == 'suggested' || status == 'later';
  }

  // ------------------------------------------------------------ doctor

  /// The doctor suggests [tests] to the patient: one tracked suggestion per
  /// test, and one card per test in their chat.
  static Future<void> suggest({
    required String chatId,
    required String patientUid,
    required String patientName,
    required String doctorUid,
    required String doctorName,
    required List<String> tests,
    String note = '',
  }) async {
    final now = DateTime.now().toIso8601String();
    for (final test in tests) {
      final ref = _db.collection(collection).doc();
      await ref.set({
        'suggestionId': ref.id,
        'chatId': chatId,
        'patientUid': patientUid,
        'patientName': patientName,
        'doctorUid': doctorUid,
        'doctorName': doctorName,
        'testName': test,
        'note': note.trim(),
        'status': 'suggested',
        'laterCount': 0,
        'createdAt': now,
      });
      final msg =
          _db.collection('chats').doc(chatId).collection('messages').doc();
      await msg.set({
        'messageId': msg.id,
        'senderUid': doctorUid,
        'senderName': doctorName,
        'type': 'test_suggestion',
        'text': 'Suggested test: $test',
        'suggestionId': ref.id,
        'testName': test,
        'note': note.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': now,
      });
    }
    await _db.collection('chats').doc(chatId).set({
      'lastMessage': 'Suggested test: ${tests.join(', ')}',
      'updatedAt': now,
      ...ChatAccessService.unreadFor(chatId, doctorUid),
    }, SetOptions(merge: true));
  }

  // ----------------------------------------------------------- patient

  /// The tests still to book (suggested, or postponed), newest first.
  static Stream<List<Map<String, dynamic>>> openForPatient(String patientUid) =>
      _db
          .collection(collection)
          .where('patientUid', isEqualTo: patientUid)
          .snapshots()
          .map((s) {
        final list = [
          for (final d in s.docs)
            if (isOpen(d.data())) {...d.data(), 'suggestionId': d.id}
        ]..sort((a, b) => (b['createdAt'] ?? '')
            .toString()
            .compareTo((a['createdAt'] ?? '').toString()));
        return list;
      });

  static Stream<Map<String, dynamic>?> watch(String id) => _db
      .collection(collection)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? ({...?d.data(), 'suggestionId': d.id}) : null);

  /// Suggestions for this patient that are due for a reminder now.
  static Future<List<Map<String, dynamic>>> due(String patientUid) async {
    try {
      final snap = await _db
          .collection(collection)
          .where('patientUid', isEqualTo: patientUid)
          .get();
      final now = DateTime.now();
      final list = [
        for (final d in snap.docs)
          if (isDue(d.data(), now: now)) {...d.data(), 'suggestionId': d.id}
      ];
      list.sort((a, b) => (a['createdAt'] ?? '')
          .toString()
          .compareTo((b['createdAt'] ?? '').toString()));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// "Book later": schedules the next reminder, or says the other options
  /// should be shown (and stops reminding) once the reminders are used up.
  static Future<LaterResult> bookLater(Map<String, dynamic> s) async {
    final id = (s['suggestionId'] ?? '').toString();
    final count = (s['laterCount'] as num?)?.toInt() ?? 0;
    final step = onBookLater(count);
    final ref = _db.collection(collection).doc(id);
    if (step.result == LaterResult.scheduled) {
      await ref.update({
        'status': 'later',
        'laterCount': count + 1,
        'remindAt': step.remindAt!.toIso8601String(),
      });
    } else {
      await ref.update({
        'status': 'closed',
        'laterCount': count + 1,
        'closedAt': DateTime.now().toIso8601String(),
        'closedReason': 'reminders used up',
      });
    }
    return step.result;
  }

  /// The patient will not book it here: stop the reminders.
  static Future<void> closeNotBooked(String id, {String reason = 'elsewhere'}) =>
      _db.collection(collection).doc(id).update({
        'status': 'closed',
        'closedAt': DateTime.now().toIso8601String(),
        'closedReason': reason,
      });

  static Future<void> markBooked(String id, {String appointmentId = ''}) =>
      _db.collection(collection).doc(id).update({
        'status': 'booked',
        'bookedAt': DateTime.now().toIso8601String(),
        if (appointmentId.isNotEmpty) 'appointmentId': appointmentId,
      });

  /// A lab test was just booked in the app: any open suggestion of that test
  /// for this patient is done.
  static Future<void> markBookedByTest(
      String patientUid, String testName, String appointmentId) async {
    try {
      final snap = await _db
          .collection(collection)
          .where('patientUid', isEqualTo: patientUid)
          .get();
      for (final d in snap.docs) {
        final s = d.data();
        if (isOpen(s) &&
            (s['testName'] ?? '').toString().trim().toLowerCase() ==
                testName.trim().toLowerCase()) {
          await markBooked(d.id, appointmentId: appointmentId);
        }
      }
    } catch (_) {
      // not critical: the reminder simply stays until the patient answers it
    }
  }
}
