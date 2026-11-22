import 'package:flutter/material.dart';

import '../../services/care_duty_service.dart';
import '../../theme/app_theme.dart';
import '../agency/care/agency_duties_screen.dart';
import '../agency/care/bookings_calendar_screen.dart';
import '../agency/care/doctors_on_leave_screen.dart';
import '../agency/care/earnings_screen.dart';
import '../agency/care/leave_requests_screen.dart';
import '../agency/nurse/nurse_leave_requests_screen.dart';

/// The freelancers' panel in the admin portal: the same modules a partner
/// agency has (calendar, duties, leave and earnings), for the care physicians
/// who work without an agency. MyDox is their agency: the leave of a
/// freelancer comes here for approval, and what freelancers earn the platform
/// shows under Earnings.
class FreelancersPanel extends StatelessWidget {
  const FreelancersPanel({super.key});

  static const String id = CareDutyService.platformId;

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final tiles = <(IconData, String, String, Widget Function())>[
      (
        Icons.currency_rupee_rounded,
        'Freelancer earnings',
        'What freelancers\' completed locum shifts earn the platform',
        () => Scaffold(
              appBar: AppBar(title: const Text('Freelancer earnings')),
              body: const EarningsView(forAdmin: true, freelancers: true),
            ),
      ),
      (
        Icons.calendar_month_rounded,
        'Bookings & Calendar',
        'Pick a date: locum and full time, duty, shift, doctors',
        () => const AgencyBookingsScreen(agencyId: id),
      ),
      (
        Icons.assignment_ind_outlined,
        'Doctors duties',
        'Which freelancer works where, and when',
        () => const AgencyDutiesScreen(agencyId: id),
      ),
      (
        Icons.pending_actions_rounded,
        'Leave requests',
        'Approve or decline freelancers\' leave',
        () => const LeaveRequestsScreen(
            approverId: id, title: 'Freelancer leave requests'),
      ),
      (
        Icons.event_busy_rounded,
        'Doctors on leave',
        'Who is on leave today',
        () => const DoctorsOnLeaveScreen(agencyId: id),
      ),
      (
        Icons.pending_actions_rounded,
        'Freelance nurse leave requests',
        'Approve or decline the leave of nurses without an agency',
        () => const NurseLeaveRequestsScreen(
            approverId: id, title: 'Freelance nurse leave requests'),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
              'Freelancers (care physicians without an agency). MyDox is their agency.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ),
        for (final t in tiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(context, t.$4()),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE0F2FE),
                      child: Icon(t.$1, color: const Color(0xFF075985)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppTheme.darkNavy)),
                            Text(t.$3,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppTheme.textMuted)),
                          ]),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppTheme.textMuted),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
