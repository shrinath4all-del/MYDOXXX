import '../../../utils/ist_timestamp.dart';
import '../../../utils/ist_clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/care_duty_roster.dart';
import '../../../services/care_agency_service.dart';
import '../../../services/care_earnings.dart';
import '../../../services/care_physician_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/responsive.dart';
import '../../../utils/stream_cache.dart';
import '../../care_physician/my_duties_view.dart' show clockText;
import '../control_room_widgets.dart' show formatInr;
import 'physician_photo.dart';

String _rupees(int n) => formatInr(n);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];

/// What the platform earns from care physician duties. The admin sees MyDox's
/// 25 % of the margin, an agency (Sai Services) its 75 %. Shows today, this
/// month, this year, and any chosen date with the physicians who worked.
class EarningsView extends StatefulWidget {
  /// true: the admin's view (MyDox's share); false: the agency's.
  final bool forAdmin;

  /// The agency whose duties count. Null (admin only) = every agency.
  final String? agencyId;

  /// The admin's freelancers panel: what freelancers' locum shifts earn the
  /// platform (the whole margin, as there is no agency).
  final bool freelancers;
  const EarningsView(
      {super.key,
      required this.forAdmin,
      this.agencyId,
      this.freelancers = false});

  @override
  State<EarningsView> createState() => _EarningsViewState();
}

class _EarningsViewState extends State<EarningsView> {
  final StreamCache _streams = StreamCache();
  late DateTime _picked = CareDutyClock.today(IstClock.now());

  String get _field => widget.freelancers
      ? 'platformShare'
      : widget.forAdmin
          ? CareEarnings.mydox
          : CareEarnings.sai;

  Stream<List<Map<String, dynamic>>> _year(int year) {
    final from = '$year-01-01', to = '$year-12-31';
    return _streams.get('$year:${widget.agencyId}:${widget.freelancers}', () {
      if (widget.freelancers) {
        return CarePhysicianService.freelancerDutiesStream(from, to);
      }
      final id = widget.agencyId;
      if (id != null && id.isNotEmpty) {
        return CareAgencyService.dutiesStream(id, from, to);
      }
      return CareAgencyService.dutiesBetweenStream(from, to);
    });
  }

  @override
  void didUpdateWidget(covariant EarningsView old) {
    super.didUpdateWidget(old);
  }

  Future<void> _pickDate() async {
    final now = IstClock.now();
    final d = await showDatePicker(
      currentDate: IstClock.now(),
      context: context,
      initialDate: DateTime(_picked.year, _picked.month, _picked.day),
      firstDate: DateTime(2025),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null) setState(() => _picked = DateTime.utc(d.year, d.month, d.day));
  }

  @override
  Widget build(BuildContext context) {
    final now = IstClock.now();
    final thisYear = CareDutyClock.today(now).year;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _year(thisYear),
      builder: (context, nowSnap) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _year(_picked.year),
        builder: (context, pickSnap) {
          final error = nowSnap.error ?? pickSnap.error;
          if (error != null) {
            return LoadErrorView(error: error, what: 'the earnings');
          }
          if (!nowSnap.hasData || !pickSnap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryTeal));
          }
          final all = nowSnap.data!;
          final key = DutySlot.dateKey(_picked);
          final onDay = pickSnap.data!;
          final dayTotal = CareEarnings.total(onDay, _field, key);
          final worked = CareEarnings.workedOn(onDay, key);
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
                  Text(
                      widget.freelancers
                          ? 'Freelancer earnings'
                          : widget.forAdmin
                          ? 'MyDox earnings'
                          : 'Sai Services earnings',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      widget.freelancers
                          ? 'The platform margin on freelancers\' completed locum shifts'
                          : widget.forAdmin
                          ? 'MyDox\'s 25% of the platform margin on completed duties'
                          : 'Sai Services\' 75% of the platform margin on completed duties',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _stat('Today', CareEarnings.today(all, _field, now))),
                const SizedBox(width: 8),
                Expanded(
                    child: _stat(_monthNames[CareDutyClock.today(now).month - 1],
                        CareEarnings.thisMonth(all, _field, now),
                        caption: 'This month')),
                const SizedBox(width: 8),
                Expanded(child: _stat('$thisYear', CareEarnings.thisYear(all, _field, now),
                    caption: 'This year')),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _card(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Pick a date',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('${_picked.day} ${_monthNames[_picked.month - 1]} ${_picked.year}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      widget.freelancers
                          ? 'Freelancer revenue'
                          : widget.forAdmin
                              ? 'MyDox earned'
                              : 'Sai Services earned',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                  Text(_rupees(dayTotal),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy)),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Care physicians who worked on this date (${worked.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 8),
              if (worked.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No care physician worked on this date.',
                      style: TextStyle(color: AppTheme.textMuted)),
                )
              else
                for (final d in worked) _workedCard(d),
            ],
          );
        },
      ),
    );
  }

  BoxDecoration _card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      );

  Widget _stat(String label, int value, {String? caption}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(caption ?? label,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_rupees(value),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.darkNavy)),
          ),
          if (caption != null)
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ]),
      );

  /// A physician who worked: photo, name, shift time and duty type.
  Widget _workedCard(Map<String, dynamic> d) {
    final a = (d['shiftStart'] as Timestamp?)?.toInstant();
    final b = (d['shiftEnd'] as Timestamp?)?.toInstant();
    final name = (d['doctorName'] ?? 'Care physician').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: _card(),
      child: Row(children: [
        PhysicianPhoto(uid: (d['doctorUserUid'] ?? '').toString(), name: name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(
                a == null || b == null
                    ? 'Shift time not recorded'
                    : '${clockText(a)} – ${clockText(b)}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
            Text(CareEarnings.dutyTypeLabel(d),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

/// The agency's own earnings screen (75 %).
class AgencyEarningsScreen extends StatelessWidget {
  final String agencyId;
  const AgencyEarningsScreen({super.key, required this.agencyId});

  @override
  Widget build(BuildContext context) => ResponsiveCenter(
        child: Scaffold(
          backgroundColor: AppTheme.bgLight,
          appBar: AppBar(title: const Text('Earnings')),
          body: EarningsView(forAdmin: false, agencyId: agencyId),
        ),
      );
}
