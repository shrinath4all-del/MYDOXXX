import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../services/agency_invite_service.dart';
import '../../services/referral_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/referral_widgets.dart';

/// Admin: "Referrals". Our marketing people (each has a link and a code to
/// hand to care physicians, nurses, technicians and physiotherapists) and
/// the permanent list of who referred whom, agencies included.
class ReferralsPanel extends StatefulWidget {
  const ReferralsPanel({super.key});

  @override
  State<ReferralsPanel> createState() => _ReferralsPanelState();
}

class _ReferralsPanelState extends State<ReferralsPanel> {
  final Stream<List<Map<String, dynamic>>> _marketers =
      ReferralService.marketersStream();
  final Stream<List<Map<String, dynamic>>> _all =
      ReferralService.referralsStream();
  bool _busy = false;

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : null));
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

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a marketing person'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration:
                const InputDecoration(labelText: 'Mobile number (optional)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    final typedName = name.text;
    final typedPhone = phone.text;
    name.dispose();
    phone.dispose();
    if (ok != true) return;
    if (typedName.trim().isEmpty) {
      _snack('Enter the person\'s name.', error: true);
      return;
    }
    await _run(() async {
      final code = await ReferralService.addMarketer(typedName, typedPhone);
      _snack('${typedName.trim()} added. Their code is $code.');
    }, 'add the person');
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('$what copied.');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(children: [
          Expanded(
            child: Text('Marketing people',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
            'Each person gets a link and a code. A care physician, nurse, '
            'technician or physiotherapist who signs up with it is noted as '
            'referred by them, permanently. Agencies have their own links in '
            'their Control Room ("Invite staff").',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _marketers,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(ErrorMessages.of(snap.error!, action: 'load the list'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No marketing people yet. Tap Add.',
                    style: TextStyle(color: AppTheme.textMuted)),
              );
            }
            return Column(children: [for (final m in snap.data!) _marketer(m)]);
          },
        ),
        const SizedBox(height: 24),
        Text('Everyone who was referred',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
        const SizedBox(height: 4),
        const Text(
            'By an agency or a marketing person, newest first. A record is '
            'written once and does not change when someone leaves an agency.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        ReferralList(stream: _all, showReferrer: true),
      ],
    );
  }

  Widget _marketer(Map<String, dynamic> m) {
    final code = (m['inviteCode'] ?? '').toString();
    final on = m['inviteActive'] != false;
    final link = code.isEmpty ? '' : AgencyInviteService.linkFor(Uri.base, code);
    final phone = (m['phone'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((m['name'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        [
                          if (phone.isNotEmpty) phone,
                          code.isEmpty ? 'making the code…' : 'Code $code',
                          if (!on) 'switched off',
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted)),
                  ]),
            ),
            Switch(
              value: on,
              onChanged: _busy
                  ? null
                  : (v) => _run(
                      () => ReferralService.setMarketerActive(
                          m['id'].toString(), v),
                      'change the link'),
            ),
          ]),
          if (code.isNotEmpty)
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: on ? () => _copy(link, 'Link') : null,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copy link'),
              ),
              TextButton.icon(
                onPressed: on ? () => _copy(code, 'Code') : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(
                              title: Text('Referred by ${m['name'] ?? ''}')),
                          body: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: ReferralList(
                                stream: ReferralService.referralsOfStream(
                                    m['id'].toString())),
                          ),
                        ))),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text('Who they referred'),
              ),
            ]),
        ]),
      ),
    );
  }
}
