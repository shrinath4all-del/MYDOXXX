import 'dart:async';
import '../utils/safe_cast.dart';

import 'package:flutter/material.dart';

import '../services/care_agency_service.dart';
import '../utils/error_messages.dart';
import '../constants/app_colors.dart';

/// Doctor app: today's duties from a care physician agency, with Check in /
/// Check out. Shown only when the doctor's mobile number (or account) is on
/// an agency's doctor list.
class AgencyDutiesCard extends StatefulWidget {
  final String uid;
  final String phone;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testDuties;
  const AgencyDutiesCard(
      {super.key, required this.uid, required this.phone, this.testDuties});

  @override
  State<AgencyDutiesCard> createState() => _AgencyDutiesCardState();
}

class _AgencyDutiesCardState extends State<AgencyDutiesCard> {
  Stream<List<Map<String, dynamic>>>? _duties;
  Timer? _tick;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    // check-in opens 1 h before the shift: refresh the buttons
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.testDuties != null) {
      setState(() => _duties = widget.testDuties);
      return;
    }
    try {
      final ids =
          await CareAgencyService.linkDoctorRecords(widget.uid, widget.phone);
      if (!mounted || ids.isEmpty) return;
      setState(() =>
          _duties = CareAgencyService.myDutiesStream(ids, DateTime.now()));
    } catch (_) {
      // Not with an agency (or offline): show nothing
    }
  }

  Future<void> _run(String id, Future<void> Function() action,
      String done) async {
    setState(() => _busy.add(id));
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(done), backgroundColor: AppColors.successDark));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ErrorMessages.of(e, action: 'update your duty')),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  static String _hm(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_duties == null) return const SizedBox.shrink();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _duties,
      builder: (context, snap) {
        final duties = snap.data ?? const [];
        if (duties.isEmpty) return const SizedBox.shrink();
        final now = DateTime.now();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.badge_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text('My agency duties today',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ]),
              for (final d in duties) ...[
                const Divider(height: 20),
                _duty(d, now),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _duty(Map<String, dynamic> d, DateTime now) {
    final id = d['id'].toString();
    final start = CareAgencyService.asTime(d['shiftStart']);
    final end = CareAgencyService.asTime(d['shiftEnd']);
    final checkIn = CareAgencyService.asTime(d['checkInAt']);
    final checkOut = CareAgencyService.asTime(d['checkOutAt']);
    final state = CareAgencyService.dutyState(d, now);
    final type = CareAgencyService.typeLabels[d['type']] ?? '';
    final unit = CareAgencyService.unitLabels[d['unit']] ?? '';
    final busy = _busy.contains(id);

    String statusText;
    Color color;
    switch (state) {
      case 'completed':
        statusText = 'Completed · ${_hm(checkIn)}–${_hm(checkOut)}';
        color = AppColors.successDark;
      case 'on_duty':
        final late = toNum(d['lateMinutes'])?.toInt() ?? 0;
        statusText =
            'On duty since ${_hm(checkIn)}${late > 0 ? ' · late $late min' : ''}';
        color = AppColors.successDark;
      case 'absent':
        statusText = 'Marked absent';
        color = AppColors.danger;
      case 'late':
        statusText =
            'Late: shift started at ${_hm(start)}. Check in now.';
        color = AppColors.orange;
      default:
        statusText = 'Shift ${_hm(start)}–${_hm(end)}';
        color = AppColors.muted;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text((d['hospitalName'] ?? 'Hospital').toString(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
            '$type${d['type'] == 'emergency' || unit.isEmpty ? '' : ' · $unit'} · ${_hm(start)}–${_hm(end)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(statusText,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        if (CareAgencyService.canCheckIn(d, now) ||
            CareAgencyService.canCheckOut(d)) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: busy
                  ? null
                  : CareAgencyService.canCheckOut(d)
                      ? () => _run(id, () => CareAgencyService.checkOut(id),
                          'Checked out. Duty completed.')
                      : () => _run(id, () async {
                            final late = await CareAgencyService.checkIn(id);
                            if (late > 0 && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Checked in $late min late.')));
                            }
                          }, 'Checked in.'),
              icon: Icon(CareAgencyService.canCheckOut(d)
                  ? Icons.logout_rounded
                  : Icons.login_rounded),
              label: Text(
                  CareAgencyService.canCheckOut(d) ? 'Check out' : 'Check in'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CareAgencyService.canCheckOut(d)
                    ? AppColors.successDark
                    : AppColors.primary,
              ),
            ),
          ),
        ] else if (state == 'scheduled' && start != null)
          Text('Check-in opens at ${_hm(start.subtract(CareAgencyService.checkInOpensBefore))}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}
