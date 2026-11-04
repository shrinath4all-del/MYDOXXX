import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../constants/app_colors.dart';

/// Sends an SMS code to [phone] and asks the user to type it.
/// Resolves to true when the number was verified (the user is then signed in
/// to Firebase), false if the user cancelled.
Future<bool> showPhoneOtpDialog(
  BuildContext context, {
  required AuthService authService,
  required String phone,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OtpDialog(authService: authService, phone: phone),
  );
  return result == true;
}

class _OtpDialog extends StatefulWidget {
  final AuthService authService;
  final String phone;
  const _OtpDialog({required this.authService, required this.phone});

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _codeController = TextEditingController();
  Timer? _cooldownTimer;
  int _cooldown = 0;
  bool _sending = true;
  bool _verifying = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.authService.sendOtp(widget.phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      // The sending step's own message names the exact Firebase check that
      // failed (fingerprint, reCAPTCHA, quota), so show it as it is instead of
      // the generic fallback.
      debugPrint('OTP send failed: $e');
      final raw = e.toString();
      final message = raw.startsWith('Exception: ') && raw.length > 11
          ? raw.substring(11).trim()
          : ErrorMessages.of(e, action: 'send the OTP');
      setState(() {
        _sending = false;
        _error = message;
      });
      // Firebase blocked OTPs for a while: tapping "Try again" right away
      // only extends the block
      if (message.toLowerCase().contains('too many')) _startCooldown(120);
    }
  }

  void _startCooldown([int seconds = 30]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.authService.verifyOtp(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = ErrorMessages.of(e, action: 'verify the OTP');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final masked = AuthService.normalizePhone(widget.phone);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.sms_outlined, color: AppTheme.primaryTeal),
          SizedBox(width: 8),
          Flexible(child: Text('Verify your number')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sending
                ? 'Sending OTP to $masked…'
                : (_sent
                    ? 'Enter the 6-digit OTP sent to $masked'
                    : 'Could not send the OTP to $masked'),
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          if (_sent)
            TextField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration:
                  const InputDecoration(hintText: '••••••', counterText: ''),
              onSubmitted: (_) => _verify(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: (_sending || _verifying || _cooldown > 0) ? null : _send,
            child: Text(_cooldown > 0
                ? (_sent
                    ? 'Resend OTP in ${_cooldown}s'
                    : 'Try again in ${_cooldown}s')
                : (_sent ? 'Resend OTP' : 'Try again')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _verifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
        ),
        ElevatedButton(
          onPressed: (_sent && !_verifying) ? _verify : null,
          child: _verifying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Verify'),
        ),
      ],
    );
  }
}
