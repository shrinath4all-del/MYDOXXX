import 'package:flutter/material.dart';

import '../models/user_model.dart';
import 'app_alert_dialog.dart';

/// Shown when someone whose registration the admin has not approved yet
/// tries to request or accept a service.
const String verificationPendingMessage =
    'Your registration is pending verification. The admin is reviewing your '
    'documents. You can use this once it is approved.';

/// True when [verified]; otherwise explains and returns false.
Future<bool> ensureVerified(BuildContext context, bool verified,
    {String what = 'request services'}) async {
  if (verified) return true;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(children: [
        Icon(Icons.pending_actions_rounded, color: Colors.orange),
        SizedBox(width: 8),
        Expanded(child: Text('Verification pending')),
      ]),
      content: Text(
          'You cannot $what until your registration is verified. The admin is reviewing your documents.',
          style: const TextStyle(height: 1.4)),
      actions: [
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
  return false;
}

/// For a booking screen: an unverified requester (a hospital still waiting
/// for approval) is taken back with the explanation. Patients are always
/// verified.
void guardVerifiedRequester(BuildContext context, UserModel requester) {
  if (requester.role != 'hospital' || requester.isVerified) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) return;
    await ensureVerified(context, false);
    if (context.mounted) Navigator.of(context).maybePop();
  });
}
