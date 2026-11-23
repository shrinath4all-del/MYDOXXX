import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../services/agency_invite_service.dart';
import '../../services/care_agency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/ist_clock.dart';
import '../../widgets/app_dialog.dart';

/// Agency: "Invite staff". The agency's invite link and code (staff who sign
/// up with it join at once), and the join requests from staff who picked the
/// agency from the list without a code (approve or reject).
class AgencyStaffInviteScreen extends StatefulWidget {
  final String agencyId;
  final InviteRole role;

  const AgencyStaffInviteScreen(
      {super.key, required this.agencyId, required this.role});

  @override
  State<AgencyStaffInviteScreen> createState() =>
      _AgencyStaffInviteScreenState();
}

class _AgencyStaffInviteScreenState extends State<AgencyStaffInviteScreen> {
  late final Stream<Map<String, dynamic>> _agency =
      CareAgencyService.agencyStream(widget.agencyId);
  late final Stream<List<Map<String, dynamic>>> _requests =
      AgencyInviteService.requestsStream(widget.role, widget.agencyId);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // the first visit makes the agency's code
    AgencyInviteService.ensureCode(widget.agencyId).catchError((e) {
      if (mounted) _snack(ErrorMessages.of(e, action: 'make the invite code'));
      return '';
    });
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : null));
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('$what copied. Send it to your ${AgencyInviteService.staffWord(widget.role)}.');
  }

  Future<void> _run(Future<void> Function() action, String doing) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(ErrorMessages.of(e, action: doing), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newCode() async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Make a new invite code?',
      message: 'The current link and code stop working at once. Staff who '
          'already joined stay with you.',
      icon: Icons.autorenew_rounded,
      confirmLabel: 'Make new code',
    );
    if (!ok) return;
    await _run(() async {
      await AgencyInviteService.regenerate(widget.agencyId);
      _snack('New invite code ready. Share the new link.');
    }, 'make a new code');
  }

  @override
  Widget build(BuildContext context) {
    final staff = AgencyInviteService.staffWord(widget.role);
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(title: Text('Invite $staff')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _agency,
        builder: (context, snap) {
          final agency = {...?snap.data, 'id': widget.agencyId};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _inviteCard(agency, staff),
              const SizedBox(height: 20),
              // care physicians and nurses who pick the agency from the list
              // are in the Control Room's own "Join requests" screen
              if (widget.role != InviteRole.therapist)
                Text(
                    '$staff who pick ${agency['name'] ?? 'your agency'} from the list without your code send a request: see "Join requests" in your Control Room to approve or reject them.',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted))
              else ...[
              Text('Join requests',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
              const SizedBox(height: 4),
              Text(
                  '$staff who picked ${agency['name'] ?? 'your agency'} from the list without your code. They work as freelancers until you approve them.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              _requestsList(agency),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _inviteCard(Map<String, dynamic> agency, String staff) {
    final code = (agency['inviteCode'] ?? '').toString();
    final on = agency['inviteActive'] != false;
    final link = code.isEmpty ? '' : AgencyInviteService.linkFor(Uri.base, code);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your invite link',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
          const SizedBox(height: 4),
          Text(
              'Send this link or code to your $staff. Whoever signs up with it, '
              'or enters the code in their profile, joins ${agency['name'] ?? 'your agency'} '
              'at once. Nobody else can join you without your approval.',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 14),
          if (code.isEmpty)
            const Center(child: CircularProgressIndicator())
          else ...[
            SelectableText(code,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: on ? AppColors.primary : AppTheme.textMuted)),
            const SizedBox(height: 6),
            SelectableText(link,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: on ? () => _copy(link, 'Invite link') : null,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copy link'),
              ),
              OutlinedButton.icon(
                onPressed: on ? () => _copy(code, 'Invite code') : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _newCode,
                icon: const Icon(Icons.autorenew_rounded, size: 18),
                label: const Text('Make a new code'),
              ),
            ]),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: _busy
                  ? null
                  : (v) => _run(
                      () => AgencyInviteService.setActive(widget.agencyId, v),
                      'change the invite link'),
              title: const Text('Invite link is on',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  on
                      ? 'New $staff can join with it.'
                      : 'Switched off: the link and code do not work.',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _requestsList(Map<String, dynamic> agency) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _requests,
        builder: (context, snap) {
          if (snap.hasError) {
            return Text(ErrorMessages.of(snap.error!, action: 'load requests'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No requests waiting.',
                  style: TextStyle(color: AppTheme.textMuted)),
            );
          }
          return Column(children: [for (final s in list) _requestTile(s, agency)]);
        },
      );

  Widget _requestTile(Map<String, dynamic> s, Map<String, dynamic> agency) {
    final name = (s['name'] ?? 'Unnamed').toString();
    final req = AgencyInviteService.requestOf(s) ?? const {};
    final at = IstClock.tryParse((req['at'] ?? '').toString());
    final details = [
      (s['qualification'] ?? '').toString(),
      (s['phone'] ?? s['mobileNumber'] ?? '').toString(),
      if (at != null) 'asked ${at.day}/${at.month}/${at.year}',
    ].where((e) => e.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (details.isNotEmpty)
                Text(details,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ]),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await AgencyInviteService.reject(
                          widget.role, s['uid'].toString());
                      _snack('Request from $name rejected.');
                    }, 'reject the request'),
            child: const Text('Reject', style: TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await AgencyInviteService.approve(widget.role, s, agency);
                      _snack('$name joined your agency.');
                    }, 'approve the request'),
            child: const Text('Approve'),
          ),
        ]),
      ),
    );
  }
}
