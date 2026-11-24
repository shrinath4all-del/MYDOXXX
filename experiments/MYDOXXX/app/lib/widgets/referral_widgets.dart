import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/agency_invite_service.dart';
import '../services/referral_service.dart';
import '../utils/ist_clock.dart';

/// "Referred by Sai Services (agency) · 23/11/2026": the permanent note of who
/// brought this person in. Nothing is shown when there is none.
class ReferredByLine extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final EdgeInsetsGeometry padding;

  const ReferredByLine(this.profile,
      {super.key, this.padding = const EdgeInsets.only(top: 4)});

  /// The text of the line, or '' when the profile has no referral.
  static String textOf(Map<String, dynamic>? profile) {
    final referral = ReferralService.referralOf(profile);
    if (referral == null) return '';
    final at = IstClock.tryParse((referral['at'] ?? '').toString());
    final date = at == null ? '' : ' · ${at.day}/${at.month}/${at.year}';
    return 'Referred by ${ReferralService.describe(referral)}$date';
  }

  @override
  Widget build(BuildContext context) {
    final text = textOf(profile);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified_user_outlined,
            size: 14, color: AppColors.brand),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand)),
        ),
      ]),
    );
  }
}

/// Asks for an invite or referral code and uses it for [me] (the staff
/// profile with its 'uid'): an agency's code joins that agency at once; the
/// first code used is kept as who referred them.
Future<void> enterReferralCode(
    BuildContext context, InviteRole role, Map<String, dynamic> me) async {
  final c = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Invite or referral code'),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
            hintText: 'e.g. SAI-7K3Q, or paste the link',
            helperText: 'From your agency or a BFAST team member.',
            helperMaxLines: 2),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Submit')),
      ],
    ),
  );
  c.dispose();
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final message = await ReferralService.useCode(role, me, code,
        via: ReferralService.fromProfile);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.danger));
  }
}

/// Sign-up: the referral / agency invite code, and under it who it belongs to
/// ("Referred by Sai Services"). A code that came with the sign-up link is
/// filled in and locked once it is recognised.
class ReferralCodeField extends StatefulWidget {
  final TextEditingController controller;
  final InviteRole role;

  /// The code came with the link the person opened.
  final bool fromLink;

  /// The text changed (the form may show or hide the agency list).
  final VoidCallback? onChanged;

  /// The code's owner was looked up (null: none, or not found).
  final ValueChanged<Referrer?>? onResolved;

  const ReferralCodeField({
    super.key,
    required this.controller,
    required this.role,
    this.fromLink = false,
    this.onChanged,
    this.onResolved,
  });

  @override
  State<ReferralCodeField> createState() => _ReferralCodeFieldState();
}

enum _Lookup { none, looking, done, failed }

class _ReferralCodeFieldState extends State<ReferralCodeField> {
  Timer? _wait;
  _Lookup _state = _Lookup.none;
  Referrer? _referrer;
  String _lookedUp = '';

  @override
  void initState() {
    super.initState();
    if (widget.controller.text.trim().isNotEmpty) _lookUp();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _typed() {
    widget.onChanged?.call();
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 600), _lookUp);
  }

  Future<void> _lookUp() async {
    final typed = widget.controller.text.trim();
    if (AgencyInviteService.keyOf(typed).isEmpty) {
      setState(() {
        _state = typed.isEmpty ? _Lookup.none : _Lookup.done;
        _referrer = null;
        _lookedUp = typed;
      });
      widget.onResolved?.call(null);
      return;
    }
    setState(() => _state = _Lookup.looking);
    Referrer? found;
    var failed = false;
    try {
      found = await ReferralService.resolve(typed);
    } catch (_) {
      failed = true; // e.g. not readable before sign-in: checked at sign-up
    }
    if (!mounted || widget.controller.text.trim() != typed) return;
    setState(() {
      _state = failed ? _Lookup.failed : _Lookup.done;
      _referrer = found;
      _lookedUp = typed;
    });
    widget.onResolved?.call(found);
  }

  bool get _locked =>
      widget.fromLink &&
      _state == _Lookup.done &&
      ReferralService.problem(_referrer) == null &&
      _lookedUp == widget.controller.text.trim();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: widget.controller,
        readOnly: _locked,
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) => _typed(),
        decoration: InputDecoration(
          labelText: 'Referral or agency invite code (optional)',
          hintText: 'e.g. SAI-7K3Q',
          helperText: _state == _Lookup.none
              ? 'Got a link or code from your agency or a BFAST team member?'
              : null,
          helperMaxLines: 2,
          prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.brand),
          suffixIcon: _locked
              ? const Icon(Icons.lock_outline_rounded, size: 18)
              : null,
        ),
      ),
      if (_state != _Lookup.none) ...[
        const SizedBox(height: 8),
        _note(),
      ],
    ]);
  }

  Widget _note() {
    if (_state == _Lookup.looking) {
      return const Text('Checking the code…',
          style: TextStyle(fontSize: 12, color: AppColors.brand));
    }
    if (_state == _Lookup.failed) {
      return const Text(
          'The code will be checked when your account is created.',
          style: TextStyle(fontSize: 12, color: AppColors.brand));
    }
    final note = ReferralService.signUpNote(_referrer, widget.role);
    final color = note.problem ? AppColors.danger : AppColors.brand;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!note.problem)
          Text(
              'Referred by: ${ReferralService.describe({
                    'name': _referrer!.name,
                    'type': _referrer!.type
                  })}',
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        Text(note.text, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }
}

/// The people one agency or marketing person referred (or everyone), from a
/// stream of `referrals` records.
class ReferralList extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;

  /// Also name who referred each person (the list of everyone).
  final bool showReferrer;

  const ReferralList({super.key, required this.stream, this.showReferrer = false});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Text('The list could not be loaded. Please try again.',
                style: TextStyle(color: AppColors.danger));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nobody yet.', style: TextStyle(color: Colors.black54)),
            );
          }
          return Column(children: [
            for (final r in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.verified_user_outlined,
                      color: AppColors.brand),
                  title: Text(
                      (r['staffName'] ?? '').toString().isEmpty
                          ? 'Unnamed'
                          : r['staffName'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([
                    ReferralService.summaryOf(r),
                    if (showReferrer)
                      'by ${ReferralService.describe({
                            'name': r['referrerName'],
                            'type': r['referrerType']
                          })}',
                  ].join('\n')),
                  isThreeLine: showReferrer,
                ),
              ),
          ]);
        },
      );
}
