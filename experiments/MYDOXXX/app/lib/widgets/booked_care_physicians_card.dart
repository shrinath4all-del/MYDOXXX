import '../services/lab_device.dart';
import 'package:flutter/material.dart';

import '../services/care_physician_service.dart';
import '../theme/app_theme.dart';
import '../constants/app_colors.dart';

typedef _Cp = CarePhysicianService;

/// Hospital home: the care physicians booked for this hospital's requests
/// (claimed by a doctor or assigned by a partner), today and upcoming, with
/// their partner, time, status and a call button.
class BookedCarePhysiciansCard extends StatelessWidget {
  /// The hospital's posted care physician requests (shifts it posted).
  final List<Map<String, dynamic>>? shifts;
  final DateTime now;
  final VoidCallback? onOpenAll;

  const BookedCarePhysiciansCard({
    super.key,
    required this.shifts,
    required this.now,
    this.onOpenAll,
  });

  /// Booked and not finished: claimed or on duty, ending today or later.
  static List<Map<String, dynamic>> booked(
      List<Map<String, dynamic>> shifts, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final list = [
      for (final s in shifts)
        if ((s['status'] == 'claimed' || s['status'] == 'on_duty') &&
            !(_Cp.shiftEnd(s)?.isBefore(today) ?? true))
          s
    ]..sort((a, b) => (_Cp.shiftStart(a) ?? DateTime(2100))
        .compareTo(_Cp.shiftStart(b) ?? DateTime(2100)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = shifts == null ? null : booked(shifts!, now);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.badge_outlined, color: AppTheme.primaryTeal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Booked Care Physicians${list == null ? '' : ' (${list.length})'}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkNavy),
              ),
            ),
            if (onOpenAll != null)
              TextButton(
                onPressed: onOpenAll,
                style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                child: const Text('View all'),
              ),
          ]),
          const SizedBox(height: 6),
          if (list == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'No care physician booked yet. Post a request from "Home Care (Care Physician)".',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            )
          else
            for (final s in list.take(5)) _row(s),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final onDuty = s['status'] == 'on_duty';
    final phone = (s['claimedByPhone'] ?? '').toString();
    final partner = (s['claimedAgencyName'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.12),
          child: const Icon(Icons.medical_services_outlined,
              color: AppTheme.primaryTeal, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((s['claimedByName'] ?? 'Care physician').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
              Text(
                [
                  '${_Cp.dayLabel(s, now)} · ${_Cp.timeRange(s)}',
                  _Cp.dutyLabel(s['dutyType']?.toString()),
                  if (partner.isNotEmpty) 'via $partner',
                ].join(' · '),
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: onDuty ? AppColors.successTint : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(onDuty ? 'On duty' : 'Booked',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: onDuty ? AppColors.successDeep : AppColors.primaryDark)),
        ),
        if (phone.isNotEmpty)
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_rounded, color: AppTheme.primaryTeal),
            onPressed: () => labLaunchUrl(Uri(scheme: 'tel', path: phone)),
          ),
      ]),
    );
  }
}
