import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user_model.dart';
import '../screens/patient/book_technician_screen.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/test_suggestion_service.dart';
import '../utils/error_messages.dart';
import '../utils/ist_clock.dart';
import 'app_alert_dialog.dart';

// ======================================================================
// Doctor: suggest tests to the patient from the chat
// ======================================================================

/// Bottom sheet where the doctor picks one or more tests (from the same list
/// patients book from), adds a note and sends them to the patient's chat.
Future<void> showSuggestTestSheet(
  BuildContext context, {
  required String chatId,
  required String patientUid,
  required String patientName,
  required String doctorUid,
  required String doctorName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SuggestTestSheet(
      chatId: chatId,
      patientUid: patientUid,
      patientName: patientName,
      doctorUid: doctorUid,
      doctorName: doctorName,
    ),
  );
}

class _SuggestTestSheet extends StatefulWidget {
  final String chatId, patientUid, patientName, doctorUid, doctorName;
  const _SuggestTestSheet({
    required this.chatId,
    required this.patientUid,
    required this.patientName,
    required this.doctorUid,
    required this.doctorName,
  });

  @override
  State<_SuggestTestSheet> createState() => _SuggestTestSheetState();
}

class _SuggestTestSheetState extends State<_SuggestTestSheet> {
  final _note = TextEditingController();
  final _search = TextEditingController();
  final Set<String> _picked = {};
  List<String> _tests = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.getLabTestsWithPrice().then((list) {
      if (!mounted) return;
      setState(() {
        _tests = [for (final t in list) t['name'] as String];
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_picked.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await TestSuggestionService.suggest(
        chatId: widget.chatId,
        patientUid: widget.patientUid,
        patientName: widget.patientName,
        doctorUid: widget.doctorUid,
        doctorName: widget.doctorName,
        tests: _picked.toList(),
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ErrorMessages.messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'send the suggestion'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final t in _tests)
        if (q.isEmpty || t.toLowerCase().contains(q)) t
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Suggest a test',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            Text(
              '${widget.patientName} will see it in the chat with a button to book it in the app, and is reminded if they do not.',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search tests (MRI, ECG, blood…)',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No test found.',
                    style: TextStyle(color: AppColors.muted)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in shown)
                    FilterChip(
                      label: Text(t),
                      selected: _picked.contains(t),
                      onSelected: (v) => setState(
                          () => v ? _picked.add(t) : _picked.remove(t)),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Note for the patient (optional)',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _picked.isEmpty || _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_picked.isEmpty
                    ? 'Choose at least one test'
                    : 'Send ${_picked.length} test${_picked.length == 1 ? '' : 's'} to patient'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The doctor typed `\` in the chat: a list of tests opens above the message
/// box (like WhatsApp's `/` menu). Several can be ticked and sent at once;
/// the letters typed after `\` filter the list.
class TestShortcutPanel extends StatelessWidget {
  final List<String> tests;
  final bool loading;
  final Set<String> picked;
  final ValueChanged<String> onToggle;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final bool sending;

  const TestShortcutPanel({
    super.key,
    required this.tests,
    required this.loading,
    required this.picked,
    required this.onToggle,
    required this.onSend,
    required this.onClose,
    this.sending = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.32;
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: AppColors.navy.withValues(alpha: 0.2),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
              child: Row(children: [
                const Icon(Icons.biotech_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Suggest tests',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                ),
              ]),
            ),
            Flexible(
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : tests.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No test found.',
                              style: TextStyle(color: AppColors.muted)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            for (final t in tests)
                              CheckboxListTile(
                                dense: true,
                                value: picked.contains(t),
                                onChanged: (_) => onToggle(t),
                                title: Text(t),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                          ],
                        ),
            ),
            if (picked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: sending ? null : onSend,
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                        'Send ${picked.length} test${picked.length == 1 ? '' : 's'} to patient'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Chat card (both sides)
// ======================================================================

/// The "Dr X suggests a test" card in the chat. The patient sees Book / Book
/// later buttons; the doctor sees where it stands.
class TestSuggestionCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final String currentUserId;
  final bool patientView;

  const TestSuggestionCard({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.patientView,
  });

  @override
  Widget build(BuildContext context) {
    final id = (message['suggestionId'] ?? '').toString();
    final test = (message['testName'] ?? '').toString();
    final note = (message['note'] ?? '').toString();
    final doctor = (message['senderName'] ?? 'Your doctor').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: StreamBuilder<Map<String, dynamic>?>(
        stream: id.isEmpty ? Stream.value(null) : TestSuggestionService.watch(id),
        builder: (context, snap) {
          final s = snap.data;
          final status = (s?['status'] ?? 'suggested').toString();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.biotech_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    patientView
                        ? '$doctor suggests a test'
                        : 'You suggested a test',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontSize: 13),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(test,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(note,
                    style: const TextStyle(
                        color: AppColors.textBody, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              if (status == 'booked')
                const _StatusChip(Icons.check_circle_rounded, 'Booked',
                    AppColors.verified)
              else if (!patientView)
                _StatusChip(
                    Icons.hourglass_empty_rounded,
                    status == 'later'
                        ? 'Patient will book later'
                        : status == 'closed'
                            ? 'Patient is not booking it here'
                            : 'Waiting for the patient',
                    AppColors.muted)
              else ...[
                if (status == 'later')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'We will remind you ${_when(s?['remindAt'])}.',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12.5),
                    ),
                  ),
                if (status == 'closed')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Reminders are off for this test.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ElevatedButton.icon(
                    onPressed: () => TestSuggestionActions.bookNow(
                        context, currentUserId, test),
                    icon: const Icon(Icons.event_available_rounded, size: 18),
                    label: Text('Book $test'),
                  ),
                  if (status == 'suggested' && s != null)
                    OutlinedButton(
                      onPressed: () =>
                          TestSuggestionActions.later(context, s, currentUserId),
                      child: const Text('Book later'),
                    ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _when(Object? iso) {
    final at = IstClock.tryParse((iso ?? '').toString());
    if (at == null) return 'soon';
    final days = at.difference(IstClock.now()).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _StatusChip(this.icon, this.text, this.color);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      );
}

// ======================================================================
// Patient home: tests the doctor suggested, as soon as they are suggested
// ======================================================================

/// "Tests your doctor suggested": one card per test still to book, with
/// Book and Book later. Nothing shows when there are none.
class TestSuggestionHomeList extends StatelessWidget {
  final UserModel patient;
  const TestSuggestionHomeList({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: TestSuggestionService.openForPatient(patient.uid),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tests your doctor suggested',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink)),
              const SizedBox(height: 8),
              for (final s in list) _card(context, s),
            ],
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> s) {
    final test = (s['testName'] ?? '').toString();
    final doctor = (s['doctorName'] ?? 'Your doctor').toString();
    final note = (s['note'] ?? '').toString();
    final later = (s['status'] ?? '') == 'later';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.biotech_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$doctor suggests',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(test,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(note,
                style:
                    const TextStyle(color: AppColors.textBody, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: () => TestSuggestionActions.bookNow(
                  context, patient.uid, test,
                  patient: patient),
              icon: const Icon(Icons.event_available_rounded, size: 18),
              label: Text('Book $test'),
            ),
            if (!later)
              OutlinedButton(
                onPressed: () => TestSuggestionActions.later(
                    context, s, patient.uid,
                    patient: patient),
                child: const Text('Book later'),
              ),
          ]),
        ],
      ),
    );
  }
}

// ======================================================================
// Patient actions and the reminder popup
// ======================================================================

class TestSuggestionActions {
  TestSuggestionActions._();

  /// Opens the lab test booking for [test], on that test's technicians.
  static Future<void> bookNow(BuildContext context, String patientUid, String test,
      {UserModel? patient}) async {
    final p = patient ?? await AuthService().getCurrentUserModel();
    if (p == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookTechnicianScreen(patient: p, initialTestName: test),
    ));
  }

  /// "Book later": schedules the reminder, or, when the reminders are used
  /// up, shows the other options.
  static Future<void> later(
      BuildContext context, Map<String, dynamic> s, String patientUid,
      {UserModel? patient}) async {
    try {
      final result = await TestSuggestionService.bookLater(s);
      if (!context.mounted) return;
      if (result == LaterResult.showOtherOptions) {
        await showOtherTestOptions(context, s, patientUid, patient: patient);
      } else {
        ErrorMessages.messengerKey.currentState?.showSnackBar(const SnackBar(
            content: Text('Okay, we will remind you about this test.')));
      }
    } catch (e) {
      ErrorMessages.messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'save your choice'))));
    }
  }
}

/// What the patient is offered when they will not (or did not) book the test
/// here.
///
/// TODO(client): the options are still to be decided with the client. For now
/// the only one is choosing another technician for the same test. Add the
/// others (callback, upload a report, stop reminders…) as tiles below.
Future<void> showOtherTestOptions(
  BuildContext context,
  Map<String, dynamic> s,
  String patientUid, {
  UserModel? patient,
}) {
  final test = (s['testName'] ?? '').toString();
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Other options for your $test',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(ctx),
            ),
          ]),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: AppColors.primarySoft,
              child: Icon(Icons.groups_rounded, color: AppColors.primary),
            ),
            title: const Text('Choose another technician'),
            subtitle: const Text('Compare who is near you, with prices'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(ctx);
              TestSuggestionActions.bookNow(context, patientUid, test,
                  patient: patient);
            },
          ),
        ],
      ),
    ),
  );
}

/// A popup that reminds the patient of a test their doctor suggested and
/// they have not booked. Shown when the patient opens the app or a chat.
class TestSuggestionPrompt {
  TestSuggestionPrompt._();

  static final Set<String> _shownThisSession = {};
  static bool _busy = false;

  static Future<void> checkAndShow(
    BuildContext context, {
    required String patientUid,
    UserModel? patient,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      final due = await TestSuggestionService.due(patientUid);
      final next = due.cast<Map<String, dynamic>?>().firstWhere(
            (s) => !_shownThisSession.contains(s!['suggestionId']),
            orElse: () => null,
          );
      if (next == null || !context.mounted) return;
      _shownThisSession.add(next['suggestionId'].toString());
      await _show(context, next, patientUid, patient);
    } finally {
      _busy = false;
    }
  }

  static Future<void> _show(BuildContext context, Map<String, dynamic> s,
      String patientUid, UserModel? patient) async {
    final test = (s['testName'] ?? '').toString();
    final doctor = (s['doctorName'] ?? 'Your doctor').toString();
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          const Icon(Icons.biotech_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Reminder: $test')),
        ]),
        content: Text(
            '$doctor suggested you get a $test done. Would you like to book it now?',
            style: const TextStyle(height: 1.4)),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'elsewhere'),
              child: const Text("I'll book elsewhere")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'later'),
              child: const Text('Remind me later')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'now'),
              child: Text('Book $test')),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'now':
        await TestSuggestionActions.bookNow(context, patientUid, test,
            patient: patient);
      case 'later':
        await TestSuggestionActions.later(context, s, patientUid,
            patient: patient);
      case 'elsewhere':
        await TestSuggestionService.closeNotBooked(
            s['suggestionId'].toString());
        if (context.mounted) {
          await showOtherTestOptions(context, s, patientUid, patient: patient);
        }
    }
  }
}
