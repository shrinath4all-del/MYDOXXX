import 'package:flutter/material.dart';

import '../../services/care_physician_service.dart';
import '../../services/nurse_staffing_service.dart';
import '../../services/technician_staffing_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/responsive.dart';
import '../agency/care/earnings_screen.dart';

/// The admin's earnings: MyDox's 25 % of the margin on care physician duties,
/// for every agency (Sai Services) together or one agency.
class AdminEarningsScreen extends StatefulWidget {
  const AdminEarningsScreen({super.key});

  @override
  State<AdminEarningsScreen> createState() => _AdminEarningsScreenState();
}

class _AdminEarningsScreenState extends State<AdminEarningsScreen> {
  String? _agencyId; // null: all
  final _agencies = CarePhysicianService.careAgenciesStream().asBroadcastStream();
  final _nurseAgencies = NurseStaffingService.careAgenciesStream().asBroadcastStream();
  final _techAgencies =
      TechnicianStaffingService.careAgenciesStream().asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: AppBar(title: const Text('MyDox earnings')),
        body: Column(children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _agencies,
            builder: (context, careSnap) => StreamBuilder<List<Map<String, dynamic>>>(
            stream: _nurseAgencies,
            builder: (context, nurseSnap) =>
                StreamBuilder<List<Map<String, dynamic>>>(
            stream: _techAgencies,
            builder: (context, techSnap) {
              final list = [
                ...(careSnap.data ?? const []),
                ...(nurseSnap.data ?? const []),
                ...(techSnap.data ?? const []),
              ];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DropdownButtonFormField<String?>(
                  value: list.any((a) => a['id'] == _agencyId) ? _agencyId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Agency'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All agencies')),
                    for (final a in list)
                      DropdownMenuItem<String?>(
                          value: a['id'].toString(),
                          child: Text((a['name'] ?? '').toString(),
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _agencyId = v),
                ),
              );
            },
          ))),
          Expanded(
            child: EarningsView(
                key: ValueKey(_agencyId), forAdmin: true, agencyId: _agencyId),
          ),
        ]),
      ),
    );
  }
}
