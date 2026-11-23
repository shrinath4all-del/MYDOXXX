import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/form_utils.dart';
import '../../utils/validators.dart';
import 'login_screen.dart';

/// "Set a new password": opened from the link in the password email
/// (a new agency login, or "Forgot password?"). The link works once and for
/// 15 minutes; an old or used link offers to send a new one.
class ResetPasswordScreen extends StatefulWidget {
  final String oobCode;
  const ResetPasswordScreen({super.key, required this.oobCode});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _Stage { checking, ready, expired, done }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _resendEmail = TextEditingController();
  _Stage _stage = _Stage.checking;
  String _email = '';
  String _expiredWhy = '';
  bool _saving = false;
  bool _show = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _resendEmail.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final email =
          await FirebaseAuth.instance.verifyPasswordResetCode(widget.oobCode);
      if (!await AuthService.resetLinkFresh(email)) {
        _expire(email,
            'This link is older than ${AuthService.resetLinkMinutes} minutes.');
        return;
      }
      if (mounted) {
        setState(() {
          _email = email;
          _stage = _Stage.ready;
        });
      }
    } on FirebaseAuthException catch (e) {
      _expire(
          '',
          switch (e.code) {
            'expired-action-code' => 'This link has expired.',
            'invalid-action-code' =>
              'This link was already used, or a newer link was sent.',
            'user-disabled' => 'This account has been disabled.',
            'user-not-found' => 'There is no account for this link.',
            _ => 'This link cannot be used.',
          });
    } catch (_) {
      _expire('', 'This link cannot be used.');
    }
  }

  void _expire(String email, String why) {
    if (!mounted) return;
    _resendEmail.text = email;
    setState(() {
      _email = email;
      _expiredWhy = why;
      _stage = _Stage.expired;
    });
  }

  Future<void> _save() async {
    if (!FormUtils.validate(_formKey)) return;
    setState(() => _saving = true);
    try {
      // checked again: the page may have been open for a while
      if (!await AuthService.resetLinkFresh(_email)) {
        _expire(_email,
            'This link is older than ${AuthService.resetLinkMinutes} minutes.');
        return;
      }
      await FirebaseAuth.instance.confirmPasswordReset(
          code: widget.oobCode, newPassword: _password.text);
      if (mounted) setState(() => _stage = _Stage.done);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'expired-action-code' || e.code == 'invalid-action-code') {
        _expire(_email, 'This link has expired or was already used.');
      } else if (mounted) {
        _snack(e.code == 'weak-password'
            ? 'Choose a stronger password.'
            : AuthService.handleAuthException(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resend() async {
    final err = Validators.email(_resendEmail.text);
    if (err != null) {
      _snack(err);
      return;
    }
    setState(() => _sending = true);
    try {
      await AuthService.sendResetLink(_resendEmail.text);
      _snack(
          'A new link was sent to ${_resendEmail.text.trim()}. It works for ${AuthService.resetLinkMinutes} minutes.',
          ok: true);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: ok ? AppColors.successDark : AppColors.danger,
    ));
  }

  void _toLogin() => Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line),
                ),
                child: switch (_stage) {
                  _Stage.checking => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  _Stage.ready => _form(),
                  _Stage.expired => _expired(),
                  _Stage.done => _done(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(IconData icon, String title, String text, {Color? color}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 36, color: color ?? AppColors.brand),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.darkNavy)),
        const SizedBox(height: 6),
        Text(text,
            style: const TextStyle(
                fontSize: 13.5, height: 1.4, color: AppTheme.textMuted)),
        const SizedBox(height: 18),
      ]);

  Widget _form() => Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(Icons.lock_reset_rounded, 'Set a new password',
              'For $_email. At least 8 characters, with a letter and a number.'),
          TextFormField(
            controller: _password,
            obscureText: !_show,
            validator: Validators.newPassword,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide' : 'Show',
                icon: Icon(_show
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: !_show,
            validator: (v) => (v ?? '').isEmpty
                ? 'Enter the password again'
                : v != _password.text
                    ? 'The passwords do not match'
                    : null,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save new password'),
          ),
        ]),
      );

  Widget _expired() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
              Icons.timer_off_outlined,
              'This link has expired',
              '$_expiredWhy A password link works once and for '
                  '${AuthService.resetLinkMinutes} minutes. Send yourself a new one.',
              color: AppColors.warning),
          TextField(
            controller: _resendEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Your email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _sending ? null : _resend,
            child: Text(_sending ? 'Sending…' : 'Send a new link'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _toLogin, child: const Text('Back to login')),
        ],
      );

  Widget _done() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(Icons.check_circle_rounded, 'Password saved',
              'Your new password is set. Log in with $_email and the new password.',
              color: AppColors.successDark),
          ElevatedButton(onPressed: _toLogin, child: const Text('Go to login')),
        ],
      );
}
