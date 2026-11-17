import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../screens/auth/login_screen.dart';
import '../services/auth_service.dart';
import '../utils/error_messages.dart';
import 'app_dialog.dart';
import '../config/test_lab_config.dart';

/// "Delete account" at the bottom of every login's profile, like Facebook /
/// Instagram: asks twice (what happens, then "type DELETE"), deactivates the
/// account at once and deletes it for good after 30 days; logging in again
/// before then offers to keep it (see [checkScheduledDeletion]).
class DeleteAccountButton extends StatefulWidget {
  const DeleteAccountButton({super.key});

  @override
  State<DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<DeleteAccountButton> {
  bool _busy = false;

  Future<void> _delete() async {
    final sure = await AppDialog.confirm(
      context,
      title: 'Delete your account?',
      message: 'Your account is deactivated now: nobody can see or book you, '
          'you get no notifications and you are signed out.\n\n'
          'It is deleted for good after ${AuthService.deletionGraceDays} days: '
          'profile, photo and documents. Changed your mind? Just log in '
          'before then and choose "Keep my account".\n\n'
          'Past bookings stay with the doctor, hospital or patient they were '
          'with.',
      icon: Icons.delete_forever_rounded,
      color: AppColors.danger,
      confirmLabel: 'Continue',
    );
    if (!sure || !mounted) return;
    if (!await _typedDelete() || !mounted) return;

    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final at = await AuthService().requestAccountDeletion();
      ErrorMessages.messengerKey.currentState?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Your account is deactivated and will be deleted on '
              '${deletionDateText(at)}. Log in before then to keep it.')));
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'delete your account')),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  /// Second step: the user types DELETE.
  Future<bool> _typedDelete() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Type DELETE to confirm'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setD(() {}),
            decoration: const InputDecoration(hintText: 'DELETE'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: c.text.trim().toUpperCase() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete my account'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    // Test lab: the shared synthetic accounts must never be deleted, and the
    // deletion functions are not deployed to the experiment project.
    if (TestLabConfig.enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
            minimumSize: const Size(0, 46),
          ),
          onPressed: _busy ? null : _delete,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_forever_rounded, size: 20),
          label: Text(_busy ? 'Deleting…' : 'Delete account'),
        ),
      ),
    );
  }
}

/// "16 Dec 2026"
String deletionDateText(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
    'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// After logging in: if this account was deleted less than 30 days ago,
/// ask whether to keep it. Returns true to carry on into the app (not
/// scheduled, or kept); false when the user stays with the deletion (they
/// are signed out).
Future<bool> checkScheduledDeletion(BuildContext context) async {
  final auth = AuthService();
  DateTime? at;
  try {
    at = await auth.scheduledDeletion();
  } catch (_) {
    return true; // can't tell (offline): never block the login for this
  }
  if (at == null || !context.mounted) return true;
  final keep = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Your account is scheduled for deletion'),
      content: Text(
        'You asked to delete this account. It will be deleted for good on '
        '${deletionDateText(at!)}.\n\nDo you want to keep your account? '
        'Everything will be just as it was.',
        style: const TextStyle(height: 1.4),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Continue deletion'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Keep my account'),
        ),
      ],
    ),
  );
  if (keep == true) {
    try {
      await auth.cancelAccountDeletion();
      ErrorMessages.messengerKey.currentState?.showSnackBar(const SnackBar(
          content: Text('Welcome back! Your account is active again.')));
      return true;
    } catch (e) {
      ErrorMessages.messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'restore your account'))));
    }
  }
  await auth.signOut();
  return false;
}
