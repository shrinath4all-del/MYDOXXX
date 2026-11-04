import '../../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/safe_cast.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/appointment_rules.dart';
import '../../constants/app_colors.dart';
import '../../utils/responsive.dart';

/// Month calendar of all appointments, with filters: Pending, Completed,
/// Urgent and SOS. Used by both doctors (their patients) and patients
/// (their doctors).
class AppointmentCalendarScreen extends StatefulWidget {
  final String uid;
  final bool forDoctor;

  const AppointmentCalendarScreen({
    super.key,
    required this.uid,
    required this.forDoctor,
  });

  @override
  State<AppointmentCalendarScreen> createState() =>
      _AppointmentCalendarScreenState();
}

class _AppointmentCalendarScreenState extends State<AppointmentCalendarScreen> {
  late DateTime _month;
  late DateTime _selected;
  String _filter = 'all';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  static const _colors = {
    'completed': AppColors.success,
    'pending': AppColors.warningBright,
    'urgent': AppColors.danger,
    'sos': AppColors.violet,
  };

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _stream = AppDatabase.instance
        .collection('appointments')
        .where(widget.forDoctor ? 'doctorUid' : 'patientUid',
            isEqualTo: widget.uid)
        .snapshots();
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _matches(Map<String, dynamic> a) =>
      _filter == 'all' || AppointmentRules.category(a) == _filter;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(title: const Text('Appointments Calendar')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryTeal));
          }
          final all = snap.data?.docs.map((d) {
                final m = d.data();
                m['appointmentId'] = d.id;
                return m;
              }).toList() ??
              [];
          final shown = all.where(_matches).toList();

          // date key -> categories present that day
          final byDay = <String, Set<String>>{};
          for (final a in shown) {
            final k = AppointmentRules.dateKey(a);
            if (k.isEmpty) continue;
            byDay.putIfAbsent(k, () => {}).add(AppointmentRules.category(a));
          }

          final dayItems = shown
              .where((a) => AppointmentRules.dateKey(a) == _key(_selected))
              .toList()
            ..sort(AppointmentRules.compareByStart);

          return Column(
            children: [
              _filters(),
              _monthHeader(),
              _weekdays(),
              _grid(byDay),
              const Divider(height: 1),
              Expanded(child: _dayList(dayItems)),
            ],
          );
        },
      ),
    ));
  }

  Widget _filters() {
    Widget chip(String id, String label, [Color? color]) {
      final sel = _filter == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          selectedColor: color ?? AppTheme.primaryTeal,
          labelStyle: TextStyle(
              color: sel ? Colors.white : AppTheme.textDark,
              fontWeight: FontWeight.bold,
              fontSize: 12),
          onSelected: (_) => setState(() => _filter = id),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          chip('all', 'All'),
          chip('pending', 'Pending', _colors['pending']),
          chip('completed', 'Completed', _colors['completed']),
          chip('urgent', 'Urgent', _colors['urgent']),
          chip('sos', 'SOS', _colors['sos']),
        ],
      ),
    );
  }

  Widget _monthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Text('${_months[_month.month - 1]} ${_month.year}',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy)),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ],
      ),
    );
  }

  Widget _weekdays() {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final n in names)
            Expanded(
              child: Center(
                child: Text(n,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(Map<String, Set<String>> byDay) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(r * 7 + c - lead + 1, daysInMonth, byDay, today)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int day, int daysInMonth, Map<String, Set<String>> byDay,
      DateTime today) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 46);
    final date = DateTime(_month.year, _month.month, day);
    final isSel = _key(date) == _key(_selected);
    final isToday = _key(date) == _key(today);
    final cats = byDay[_key(date)] ?? {};

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSel ? AppTheme.primaryTeal : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isToday ? AppTheme.primaryTeal : AppColors.line,
              width: isToday ? 1.6 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSel ? Colors.white : AppTheme.textDark)),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in ['pending', 'completed', 'urgent', 'sos'])
                  if (cats.contains(c))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                          color: isSel ? Colors.white : _colors[c],
                          shape: BoxShape.circle),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No appointments on ${_selected.day}/${_selected.month}/${_selected.year}',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _card(items[i]),
    );
  }

  Widget _card(Map<String, dynamic> a) {
    final cat = AppointmentRules.category(a);
    final color = _colors[cat]!;
    final name = (widget.forDoctor ? a['patientName'] : a['doctorName'])
            ?.toString() ??
        '';
    final status = AppointmentRules.isMissed(a)
        ? 'Not attended'
        : AppointmentRules.statusOf(a);
    final cash = a['cashCollected'] == true;
    final label = const {
      'completed': 'Completed',
      'pending': 'Pending',
      'urgent': 'Urgent',
      'sos': 'SOS',
    }[cat]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Appointment' : name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                    '${a['time'] ?? ''} · ${a['consultationType'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
                if (cat == 'completed')
                  Text(
                    cash
                        ? 'Cash collected ₹${toNum(a['price'])?.round() ?? 0}'
                        : 'Cash not recorded',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cash ? AppColors.successDark : AppColors.orange),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Text(status,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
