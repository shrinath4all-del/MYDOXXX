import 'package:flutter/material.dart';

import '../../models/care_duty_roster.dart';
import '../../services/nurse_duty_service.dart';
import '../../services/nurse_staffing_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../utils/stream_cache.dart';
import '../care_physician/cp_widgets.dart';
import '../../constants/app_colors.dart';
import '../../utils/ist_clock.dart';

typedef _Duty = NurseDutyService;

/// Colour that identifies the physician: A blue, B green, C yellow, relief
/// purple. Names and shift labels are always shown next to the colour.
Color nurseDutyColor(String letter) => switch (letter) {
      'A' => const Color(0xFF2563EB),
      'B' => const Color(0xFF16A34A),
      'C' => const Color(0xFFB7791F),
      _ => const Color(0xFF7C3AED),
    };

/// Light background behind a physician's letter (the roster pills).
Color nurseDutyTint(String letter) => switch (letter) {
      'A' => const Color(0xFFDCE8FB),
      'B' => const Color(0xFFDDF2E3),
      'C' => const Color(0xFFFBE8CF),
      _ => const Color(0xFFEBDDF7),
    };

const _teal = Color(0xFF0F9D8A);

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayText(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1].substring(0, 3)}';

/// The nurse's duty dashboard for the hospital team he is part of:
/// Home, Roster (monthly grid), Requests (leave and swaps) and My team.
class NurseDutyHomeScreen extends StatefulWidget {
  final Map<String, dynamic> me; // care_physicians doc with 'uid'
  final VoidCallback onOpenShifts; // the shifts, jobs and profile screens
  final VoidCallback onLogout;
  const NurseDutyHomeScreen({
    super.key,
    required this.me,
    required this.onOpenShifts,
    required this.onLogout,
  });

  @override
  State<NurseDutyHomeScreen> createState() => _CareDutyHomeScreenState();
}

class _CareDutyHomeScreenState extends State<NurseDutyHomeScreen> {
  final StreamCache _streams = StreamCache();
  int _tab = 0;
  String? _teamId;
  late DateTime _month = _firstOfMonth(IstClock.now());
  DateTime? _selected;

  String get _uid => widget.me['uid'].toString();
  String get _myName => (widget.me['name'] ?? 'Nurse').toString();

  static DateTime _firstOfMonth(DateTime now) {
    final t = CareDutyClock.today(now);
    return DateTime.utc(t.year, t.month, 1);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  Future<void> _run(Future<void> Function() action, String done,
      String doing) async {
    try {
      await action();
      _snack(done);
    } catch (e) {
      _snack(ErrorMessages.of(e, action: doing), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('teams', () => _Duty.teamsOf(_uid)),
        builder: (context, teamSnap) =>
            StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streams.get('requests', () => _Duty.requestsFor(_uid)),
          builder: (context, reqSnap) {
            final error = teamSnap.error ?? reqSnap.error;
            final teams = teamSnap.data ?? const [];
            final requests = reqSnap.data ?? const [];
            if (error != null) {
              return Scaffold(
                  body: LoadErrorView(error: error, what: 'your duty roster'));
            }
            if (!teamSnap.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (teams.isEmpty) {
              return Scaffold(
                backgroundColor: CpColors.page,
                body: CpEmpty('🗓️',
                    'You are not on a hospital duty team yet.',
                    action: ElevatedButton(
                        onPressed: widget.onOpenShifts,
                        child: const Text('Open shifts & jobs'))),
              );
            }
            final team = teams.firstWhere((t) => t['id'] == _teamId,
                orElse: () => teams.first);
            final teamRequests =
                requests.where((r) => r['teamId'] == team['id'] || r['type'] == 'leave').toList();
            return Scaffold(
              backgroundColor: CpColors.page,
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Back to my dashboard',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: widget.onOpenShifts,
                ),
                title: Text(const [
                  'Home',
                  'Duty roster',
                  'Requests',
                  'My team'
                ][_tab]),
                actions: [
                  if (teams.length > 1)
                    PopupMenuButton<String>(
                      tooltip: 'Hospital team',
                      icon: const Icon(Icons.swap_horiz_rounded),
                      onSelected: (id) => setState(() => _teamId = id),
                      itemBuilder: (_) => [
                        for (final t in teams)
                          PopupMenuItem(
                              value: t['id'].toString(),
                              child: Text((t['hospitalName'] ?? '').toString())),
                      ],
                    ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout_rounded),
                    onPressed: widget.onLogout,
                  ),
                ],
              ),
              body: switch (_tab) {
                1 => _rosterTab(team),
                2 => _requestsTab(team, teamRequests),
                3 => _teamTab(team),
                _ => _homeTab(team, teamRequests),
              },
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  const NavigationDestination(
                      icon: Icon(Icons.home_outlined), label: 'Home'),
                  const NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined), label: 'Roster'),
                  NavigationDestination(
                      icon: Badge(
                        isLabelVisible: _needsMe(teamRequests) > 0,
                        label: Text('${_needsMe(teamRequests)}'),
                        child: const Icon(Icons.swap_calls_rounded),
                      ),
                      label: 'Requests'),
                  const NavigationDestination(
                      icon: Icon(Icons.groups_outlined), label: 'My team'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Requests waiting for this physician's answer.
  int _needsMe(List<Map<String, dynamic>> requests) =>
      requests.where(_waitsForMe).length;

  bool _waitsForMe(Map<String, dynamic> r) {
    if (r['status'] != 'pending') return false;
    if (r['type'] == 'swap') return r['targetUid'] == _uid;
    return r['requesterUid'] != _uid &&
        NurseStaffingService.listOf(r['poolUids']).contains(_uid);
  }

  // ------------------------------------------------------------------ home

  Widget _homeTab(Map<String, dynamic> team, List<Map<String, dynamic>> requests) {
    final roster = _Duty.rosterOf(team);
    final now = IstClock.now();
    final nowInstant = IstClock.toInstant(now); // duty times are real instants
    final today = CareDutyClock.today(now);
    final mine = roster
        .dutiesOf(_uid, today.subtract(const Duration(days: 1)),
            today.add(const Duration(days: 60)))
        .where((s) => s.end.isAfter(nowInstant))
        .toList();
    final current = mine.where((s) => !s.start.isAfter(nowInstant)).firstOrNull;
    final next = mine.where((s) => s.start.isAfter(nowInstant)).firstOrNull;
    final month = DateTime.utc(today.year, today.month, 1);
    final needs = _needsMe(requests);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF075985), Color(0xFF0EA5E9)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((team['hospitalName'] ?? 'Hospital').toString(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                'You are ${roster.letterOf(_uid)} · ${(team['agencyName'] ?? '').toString()}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            Text(current != null ? 'ON DUTY NOW' : 'NEXT DUTY',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
            Text(
                (current ?? next) == null
                    ? 'No duty in the next 60 days'
                    : _slotLine(current ?? next!),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _stat('${roster.hoursIn(_uid, month)} h',
                  'scheduled in ${_months[month.month - 1]}')),
          const SizedBox(width: 10),
          Expanded(child: _stat('${mine.length}', 'duties ahead (60 days)')),
        ]),
        const SizedBox(height: 14),
        if (needs > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(children: [
              Expanded(
                  child: Text(
                      '$needs request${needs == 1 ? '' : 's'} waiting for your answer',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(
                  onPressed: () => setState(() => _tab = 2),
                  child: const Text('Open')),
            ]),
          ),
        _action(Icons.event_busy_outlined, 'Request leave',
            'Pick a future duty; a relief nurse can take it.', () {
          setState(() {
            _tab = 1;
            _selected = (next ?? current)?.date;
          });
        }),
        _action(Icons.groups_outlined, 'Team and rotation',
            'Who is A, B and C and how the weeks rotate.',
            () => setState(() => _tab = 3)),
        _action(Icons.swap_horiz_rounded, 'Move to another hospital',
            'Apply for a full-time team at a different hospital.',
            () => _openMoves(team)),
        _action(Icons.work_outline_rounded, 'Open shifts, jobs & profile',
            'Locum shifts, team requests and full-time jobs.',
            widget.onOpenShifts),
      ],
    );
  }

  /// Open full-time team requests of other hospitals: a placed physician
  /// can apply to move; the agency decides who is placed.
  Future<void> _openMoves(Map<String, dynamic> team) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _MoveSheet(
        me: widget.me,
        currentHospital: (team['hospitalName'] ?? '').toString(),
        currentHospitalId: (team['hospitalId'] ?? '').toString(),
        onDone: _snack,
      ),
    );
  }

  String _slotLine(DutySlot s) =>
      '${_dayText(s.date)} · ${s.shift.label} ${s.shift.timeText}';

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: cpCard(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: CpColors.ink)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: CpColors.muted)),
        ]),
      );

  Widget _action(IconData icon, String title, String sub, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: cpCard(),
            child: Row(children: [
              Icon(icon, color: CpColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 12, color: CpColors.muted)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: CpColors.muted),
            ]),
          ),
        ),
      );

  // ---------------------------------------------------------------- roster

  Widget _rosterTab(Map<String, dynamic> team) {
    final roster = _Duty.rosterOf(team);
    final today = CareDutyClock.today(IstClock.now());
    final daysInMonth = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final lead = _month.weekday - 1; // blank cells before the 1st
    final selected = _selected ?? (today.year == _month.year && today.month == _month.month ? today : _month);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
       Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6F5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CpColors.line),
        ),
        child: Column(children: [
        Row(children: [
          IconButton(
              onPressed: () => setState(() =>
                  _month = DateTime.utc(_month.year, _month.month - 1, 1)),
              icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Text('${_months[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          IconButton(
              onPressed: () => setState(() =>
                  _month = DateTime.utc(_month.year, _month.month + 1, 1)),
              icon: const Icon(Icons.chevron_right_rounded)),
          TextButton(
              onPressed: () => setState(() {
                    _month = DateTime.utc(today.year, today.month, 1);
                    _selected = today;
                  }),
              child: const Text('Today')),
        ]),
        Row(children: [
          for (final w in _weekdays)
            Expanded(
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: CpColors.muted))),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.7,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= daysInMonth; d++)
              _dayCell(roster, DateTime.utc(_month.year, _month.month, d), today,
                  selected),
          ],
        ),
        const SizedBox(height: 6),
        _legend(team),
        ]),
       ),
        const SizedBox(height: 12),
        _dayDetail(team, roster, selected),
      ],
    );
  }

  Widget _dayCell(CareDutyRoster roster, DateTime day, DateTime today,
      DateTime selected) {
    final isSel = day == selected;
    final isToday = day == today;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selected = day),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSel
                  ? _teal
                  : isToday
                      ? _teal.withValues(alpha: 0.4)
                      : Colors.transparent,
              width: isSel ? 1.6 : 1),
        ),
        child: Column(children: [
          Text('${day.day}',
              style: TextStyle(
                  fontSize: 11.5,
                  color: const Color(0xFF334155),
                  fontWeight: isSel || isToday ? FontWeight.w800 : FontWeight.w500)),
          const SizedBox(height: 3),
          for (final slot in roster.slotsOn(day))
            Expanded(
              child: Builder(builder: (_) {
                final letter = roster.letterOf(roster.assigneeOf(slot));
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: nurseDutyTint(letter),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(slot.shift.label[0],
                          style: const TextStyle(
                              fontSize: 9, color: Color(0xFF64748B))),
                      Text(letter,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: nurseDutyColor(letter))),
                    ],
                  ),
                );
              }),
            ),
        ]),
      ),
    );
  }

  Widget _legend(Map<String, dynamic> team) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'M 8 am-3 pm    E 3 pm-10 pm\nN 10 pm-8 am the following day',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: CpColors.muted, height: 1.5),
        ),
      );

  static String _clock(int hour) {
    final h = hour % 24;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'am' : 'pm'}';
  }

  static String _range(DutyShift s) =>
      '${_clock(s.startHour)} – ${_clock(s.startHour + s.hours)}';

  Widget _dayDetail(
      Map<String, dynamic> team, CareDutyRoster roster, DateTime day) {
    final nowInstant = IstClock.instant();
    final myNext = roster
        .slotsOn(day)
        .where((s) => roster.assigneeOf(s) == _uid && s.start.isAfter(nowInstant))
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CpColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${day.day} ${_months[day.month - 1]} · Team roster',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        for (final slot in roster.slotsOn(day)) ...[
          Builder(builder: (_) {
            final who = roster.assigneeOf(slot);
            final letter = roster.letterOf(who);
            final changed = roster.overrides.containsKey(slot.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: nurseDutyTint(letter),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(letter,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: nurseDutyColor(letter))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${slot.shift.label} · ${_Duty.assigneeName(team, slot)}'
                            '${who == _uid ? ' (you)' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(_range(slot.shift),
                            style: const TextStyle(
                                fontSize: 12.5, color: CpColors.muted)),
                        if (changed)
                          Text('Confirmed replacement',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.successDark,
                                  fontWeight: FontWeight.w600)),
                      ]),
                ),
                Text('${slot.shift.hours}h',
                    style: const TextStyle(fontSize: 12.5, color: CpColors.muted)),
              ]),
            );
          }),
        ],
        if (myNext != null) ...[
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _leaveSheet(team, myNext),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Adjust my duty'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: () => _swapSheet(team, roster, myNext),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Request a swap instead'),
              style: TextButton.styleFrom(foregroundColor: _teal),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _leaveSheet(Map<String, dynamic> team, DutySlot slot) async {
    String reason = _Duty.leaveReasons.keys.first;
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request leave · ${_dayText(slot.date)} ${slot.shift.label}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'You stay on the roster until a relief nurse accepts.',
                    style: TextStyle(color: CpColors.muted, fontSize: 12.5)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    for (final e in _Duty.leaveReasons.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setS(() => reason = v ?? reason),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 3,
                  maxLength: _Duty.maxNote,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Send leave request')),
                ),
              ]),
        ),
      ),
    );
    if (ok != true) return;
    await _run(
        () => _Duty.requestLeave(
              team: team,
              requesterUid: _uid,
              requesterName: _myName,
              slot: slot,
              reason: _Duty.leaveReasons[reason] ?? reason,
              note: note.text,
            ),
        'Leave requested. You stay on the roster until someone accepts.',
        'request leave');
    if (mounted) setState(() => _tab = 2);
  }

  Future<void> _swapSheet(
      Map<String, dynamic> team, CareDutyRoster roster, DutySlot mine) async {
    final options = [
      for (final s in roster.slotsOn(mine.date))
        if (roster.assigneeOf(s) != _uid &&
            roster.members.contains(roster.assigneeOf(s)))
          s
    ];
    if (options.isEmpty) {
      _snack('Your teammates have no duty to swap on that date.', error: true);
      return;
    }
    final theirs = await showModalBottomSheet<DutySlot>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: const Text('Swap with',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  'Your ${mine.shift.label} duty on ${_dayText(mine.date)} for:')),
          for (final s in options)
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: nurseDutyColor(roster.letterOf(roster.assigneeOf(s))),
                  child: Text(roster.letterOf(roster.assigneeOf(s)),
                      style: const TextStyle(color: Colors.white))),
              title: Text(_Duty.assigneeName(team, s)),
              subtitle: Text('${s.shift.label} · ${s.shift.timeText}'),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    );
    if (theirs == null) return;
    await _run(
        () => _Duty.requestSwap(
              team: team,
              requesterUid: _uid,
              requesterName: _myName,
              mine: mine,
              targetUid: roster.assigneeOf(theirs),
              theirs: theirs,
            ),
        'Swap requested. Both duties stay as they are until your teammate accepts.',
        'request the swap');
    if (mounted) setState(() => _tab = 2);
  }

  // -------------------------------------------------------------- requests

  Widget _requestsTab(
      Map<String, dynamic> team, List<Map<String, dynamic>> requests) {
    final waiting = requests.where(_waitsForMe).toList();
    final mine = requests.where((r) => r['requesterUid'] == _uid).toList();
    final team_ = requests
        .where((r) =>
            r['requesterUid'] != _uid &&
            !_waitsForMe(r) &&
            NurseStaffingService.listOf(r['memberUids']).contains(_uid))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (waiting.isNotEmpty) ...[
          const _Head('Needs your answer'),
          for (final r in waiting) _requestCard(r, forMe: true),
        ],
        const _Head('My requests'),
        if (mine.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('You have not asked for leave or a swap.',
                style: TextStyle(color: CpColors.muted)),
          )
        else
          for (final r in mine) _requestCard(r),
        if (team_.isNotEmpty) ...[
          const _Head('Team'),
          for (final r in team_) _requestCard(r),
        ],
      ],
    );
  }

  Widget _requestCard(Map<String, dynamic> r, {bool forMe = false}) {
    final status = (r['status'] ?? '').toString();
    final slot = DutySlot.parse((r['sourceKey'] ?? '').toString());
    final target = DutySlot.parse((r['targetKey'] ?? '').toString());
    final swap = r['type'] == 'swap';
    final (label, color) = switch (status) {
      'accepted' => ('ACCEPTED', CpColors.green),
      'withdrawn' => ('WITHDRAWN', CpColors.muted),
      'declined' => ('DECLINED', CpColors.red),
      'awaiting_hospital' => ('WITH HOSPITAL', const Color(0xFFD97706)),
      _ when !swap && (r['hospitalApprovedAt'] ?? '').toString().isNotEmpty =>
        ('APPROVED', CpColors.green),
      _ => ('PENDING', const Color(0xFFD97706)),
    };
    final mineReq = r['requesterUid'] == _uid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: cpCard(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  swap
                      ? (mineReq
                          ? 'Swap with ${r['targetName'] ?? 'teammate'}'
                          : '${r['requesterName']} wants to swap')
                      : (mineReq
                          ? 'Leave request'
                          : 'Cover needed: ${r['requesterName']}'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            CpTag(label, color),
          ]),
          const SizedBox(height: 4),
          if (slot != null)
            Text(
                swap && target != null
                    ? '${_dayText(slot.date)}: ${slot.shift.label} for ${target.shift.label}'
                    : '${_dayText(slot.date)} · ${slot.shift.label} ${slot.shift.timeText}',
                style: const TextStyle(fontSize: 12.5, color: CpColors.muted)),
          Text((r['hospitalName'] ?? '').toString(),
              style: const TextStyle(fontSize: 12.5, color: CpColors.muted)),
          if ((r['reason'] ?? '').toString().isNotEmpty && !swap)
            Text('Reason: ${r['reason']}',
                style: const TextStyle(fontSize: 12.5)),
          if (status == 'awaiting_hospital')
            const Text('Waiting for the hospital to approve your leave.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (status == 'declined' && r['hospitalDeclined'] == true)
            const Text('The hospital did not approve this leave. Your duty is unchanged.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (status == 'pending' && !swap && (r['hospitalApprovedAt'] ?? '').toString().isNotEmpty)
            const Text('The hospital approved your leave. Finding a relief physician.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (status == 'accepted' && (r['acceptedByName'] ?? '').toString().isNotEmpty)
            Text(swap
                ? 'Swapped with ${r['acceptedByName']}'
                : 'Covered by ${r['acceptedByName']}',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.successDark,
                    fontWeight: FontWeight.w600)),
          if (status == 'awaiting_hospital' && mineReq)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => _run(
                      () => _Duty.withdraw(r['id'].toString(), _uid),
                      'Request withdrawn. Your duty is unchanged.',
                      'withdraw the request'),
                  child: const Text('Withdraw')),
            ),
          if (status == 'pending') ...[
            const SizedBox(height: 8),
            if (forMe && swap)
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _run(
                          () => _Duty.declineSwap(r['id'].toString(), _uid),
                          'Swap declined.',
                          'decline the swap'),
                      child: const Text('Decline')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                      onPressed: () => _run(
                          () => _Duty.acceptSwap(r['id'].toString(), _uid),
                          'Swap accepted. Both duties changed.',
                          'accept the swap'),
                      child: const Text('Accept swap')),
                ),
              ])
            else if (forMe)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => _run(
                        () => _Duty.acceptRelief(
                            r['id'].toString(), _uid, _myName),
                        'You now cover that duty.',
                        'take the duty'),
                    child: const Text('Accept cover')),
              )
            else if (mineReq)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => _run(
                        () => _Duty.withdraw(r['id'].toString(), _uid),
                        'Request withdrawn. Your duty is unchanged.',
                        'withdraw the request'),
                    child: const Text('Withdraw')),
              ),
          ],
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ team

  Widget _teamTab(Map<String, dynamic> team) {
    final roster = _Duty.rosterOf(team);
    final names = NurseStaffingService.listOf(team['memberNames']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cpCard(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((team['hospitalName'] ?? '').toString(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text('${team['agencyName'] ?? ''} · ${team['area'] ?? ''}',
                style: const TextStyle(color: CpColors.muted, fontSize: 12.5)),
            Text('Rotation started ${team['anchor']}',
                style: const TextStyle(color: CpColors.muted, fontSize: 12.5)),
            for (final l in ((team['leaving'] as Map?) ?? const {}).values)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '${(l as Map)['name']} moves to ${l['toHospital']} from ${l['from']}. Your agency will arrange a replacement.',
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFFB45309))),
              ),
            const SizedBox(height: 12),
            for (var i = 0; i < (roster.fixed == null ? 3 : 1); i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  CircleAvatar(
                      radius: 14,
                      backgroundColor: nurseDutyColor(CareDutyRoster.letters[i]),
                      child: Text(CareDutyRoster.letters[i],
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          (i < names.length ? names[i] : '') +
                              (roster.members[i] == _uid ? ' (you)' : ''),
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        if (roster.fixed == null) ...[
        const _Head('Weekly rotation'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: cpCard(),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            children: [
              TableRow(children: [
                const _Cell('Duty', bold: true),
                for (final w in ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'])
                  _Cell(w, bold: true),
              ]),
              for (final s in DutyShift.values)
                TableRow(children: [
                  _Cell('${s.label}\n${s.timeText.split(' (').first}'),
                  for (var w = 0; w < 4; w++)
                    _Cell(CareDutyRoster.letters[(w + s._rotationOffset) % 3],
                        color: nurseDutyColor(
                            CareDutyRoster.letters[(w + s._rotationOffset) % 3])),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ],
        const _Head('Rules'),
        const Text(
            '• The shift stays the same through a 7-day week from the start date, then rotates: Morning, then Night, then Evening.\n'
            '• A request does not remove you from the roster. The duty changes only after a valid acceptance.\n'
            '• The last night of a week cannot be followed by the morning of the next week (the evening is allowed).\n'
            '• You cannot hold overlapping duties, or three duties in a row without a break.',
            style: TextStyle(height: 1.5, color: CpColors.ink)),
      ],
    );
  }
}

extension on DutyShift {
  int get _rotationOffset => switch (this) {
        DutyShift.morning => 0,
        DutyShift.evening => 1,
        DutyShift.night => 2,
      };
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: CpColors.muted)),
      );
}

class _Cell extends StatelessWidget {
  final String text;
  final bool bold;
  final Color? color;
  const _Cell(this.text, {this.bold = false, this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: bold || color != null ? FontWeight.w800 : FontWeight.w500,
                color: color ?? CpColors.ink)),
      );
}


/// Other hospitals' open full-time team requests, to apply for a move.
class _MoveSheet extends StatefulWidget {
  final Map<String, dynamic> me;
  final String currentHospital;
  final String currentHospitalId;
  final void Function(String msg, {bool error}) onDone;
  const _MoveSheet({
    required this.me,
    required this.currentHospital,
    required this.currentHospitalId,
    required this.onDone,
  });

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  final Set<String> _busy = {};

  Future<void> _apply(Map<String, dynamic> r) async {
    final id = r['id'].toString();
    setState(() => _busy.add(id));
    try {
      await NurseStaffingService.applyTeam(id, widget.me,
          currentHospital: widget.currentHospital);
      widget.onDone(
          'Applied. Your agency decides who is placed. You stay on your current team until then.');
    } catch (e) {
      widget.onDone(ErrorMessages.of(e, action: 'apply'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.me['uid'].toString();
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: NurseStaffingService.openShiftsStream(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            final now = IstClock.now();
            final list = [
              for (final r in snap.data!)
                if (NurseStaffingService.isTeam(r) &&
                    r['rotation'] == true &&
                    (r['hospitalId'] ?? '').toString() != widget.currentHospitalId &&
                    NurseStaffingService.shiftFits(r, widget.me, now) &&
                    !NurseStaffingService.listOf(r['applicantUids'])
                        .contains(widget.me['uid'].toString()))
                  r
            ];
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Move to another hospital',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    'Full-time teams other hospitals are asking for. You stay at ${widget.currentHospital} until your agency places you.',
                    style: const TextStyle(color: CpColors.muted, fontSize: 12.5)),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No other hospital is asking for a full-time team right now.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CpColors.muted)),
                  ),
                for (final r in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: cpCard(),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((r['hospitalName'] ?? '').toString(),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                              'Full-time · ${(r['fixedShift'] ?? '').toString().isEmpty ? 'weekly rotation' : '${r['fixedShift']} shift every day'} from ${r['anchor']}'
                              '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
                              style: const TextStyle(
                                  fontSize: 12.5, color: CpColors.muted)),
                          Text('₹${((r['doctorPay'] ?? r['pay']) as num?)?.round() ?? 0} per ${r['payPeriod'] == 'month' ? 'month' : 'duty'}',
                              style: const TextStyle(fontSize: 12.5)),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy.contains(r['id'].toString())
                                  ? null
                                  : () => _apply(r),
                              child: Text(
                                  NurseStaffingService.listOf(r['applicantUids'])
                                          .contains(uid)
                                      ? 'Applied'
                                      : 'Apply to move'),
                            ),
                          ),
                        ]),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
