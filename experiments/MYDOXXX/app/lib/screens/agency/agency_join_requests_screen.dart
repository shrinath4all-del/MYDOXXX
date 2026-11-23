import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../services/agency_join_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/app_alert_dialog.dart';
import '../../utils/ist_clock.dart';

/// An agency's join requests: freelancers (care physicians, nurses,
/// technicians) who asked to join, with their details, to approve or reject.
class AgencyJoinRequestsScreen extends StatefulWidget {
  final String agencyId;
  const AgencyJoinRequestsScreen({super.key, required this.agencyId});

  @override
  State<AgencyJoinRequestsScreen> createState() =>
      _AgencyJoinRequestsScreenState();
}

class _AgencyJoinRequestsScreenState extends State<AgencyJoinRequestsScreen> {
  late final Stream<List<Map<String, dynamic>>> _requests =
      AgencyJoinService.pendingStream(widget.agencyId);
  final Set<String> _busy = {};

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final name = (r['name'] ?? 'this person').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(approve ? 'Approve $name?' : 'Reject $name?'),
        content: Text(approve
            ? '$name becomes a member of your agency and can apply for full-time jobs through you.'
            : '$name stays a freelancer and is told the request was not approved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: approve
                ? null
                : ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = r['id'].toString();
    setState(() => _busy.add(id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      approve
          ? await AgencyJoinService.approve(r)
          : await AgencyJoinService.reject(r);
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? '$name is now a member of your agency.'
            : 'Request from $name rejected.'),
        backgroundColor: approve ? AppColors.successDark : AppColors.navy,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e,
            action: approve ? 'approve the request' : 'reject the request')),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(title: const Text('Join requests')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _requests,
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'join requests');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const Text(
                'Freelancers who asked to join your agency. Once you approve, '
                'they are your members and can apply for full-time jobs through you.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text('No join requests right now.',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkNavy)),
                  ),
                ),
              for (final r in list) _card(r),
            ],
          );
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final busy = _busy.contains(r['id'].toString());
    final years = r['experienceYears'];
    final list = (Object? v) => [for (final x in (v as List? ?? const [])) x.toString()];
    final rows = <(IconData, String)>[
      (Icons.work_history_outlined,
          '${years ?? 0} year${years == 1 ? '' : 's'} of experience'),
      if ((r['qualification'] ?? '').toString().isNotEmpty)
        (Icons.school_outlined, r['qualification'].toString()),
      if ((r['regNo'] ?? '').toString().isNotEmpty)
        (Icons.badge_outlined, 'Reg. no. ${r['regNo']}'),
      if ((r['phone'] ?? '').toString().isNotEmpty)
        (Icons.phone_outlined, r['phone'].toString()),
      if ((r['email'] ?? '').toString().isNotEmpty)
        (Icons.mail_outline_rounded, r['email'].toString()),
      if (list(r['areas']).isNotEmpty)
        (Icons.place_outlined, list(r['areas']).join(', ')),
    ];
    final asked = IstClock.tryParse((r['requestedAt'] ?? '').toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['name'] ?? 'Unnamed').toString(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkNavy)),
              const SizedBox(height: 2),
              Text(
                  [
                    (r['role'] ?? 'Freelancer').toString(),
                    if (asked != null)
                      'asked ${asked.day}/${asked.month}/${asked.year}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (r['isVerified'] == true
                      ? AppColors.successDark
                      : AppColors.warning)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(r['isVerified'] == true ? 'Verified' : 'Not verified',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: r['isVerified'] == true
                        ? AppColors.successDark
                        : AppColors.warning)),
          ),
        ]),
        const SizedBox(height: 10),
        for (final (icon, text) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(text,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.darkNavy))),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : () => _decide(r, false),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: busy ? null : () => _decide(r, true),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(busy ? 'Saving…' : 'Approve'),
            ),
          ),
        ]),
      ]),
    );
  }
}
