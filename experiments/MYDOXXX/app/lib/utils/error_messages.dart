import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'ist_clock.dart';

/// Turns exceptions into short messages a patient or provider can act on,
/// instead of raw text like "[cloud_firestore/unavailable] ...".
class ErrorMessages {
  ErrorMessages._();

  static const String generic = 'Something went wrong. Please try again.';
  static const String noInternet =
      'No internet connection. Check your network and try again.';

  /// Message for [error]. [action] describes what failed, e.g.
  /// "save your profile", and is used when the cause is unknown.
  static String of(Object error, {String? action}) {
    final fallback =
        action == null ? generic : 'Could not $action. Please try again.';

    if (error is FirebaseAuthException) return _auth(error.code) ?? fallback;
    if (error is FirebaseException) {
      return _firebase(error.plugin, error.code) ?? fallback;
    }
    // SocketException (no dart:io import, so this also works on web)
    if (error.runtimeType.toString().contains('SocketException')) {
      return noInternet;
    }
    if (error is TimeoutException) {
      return 'The request timed out. Check your network and try again.';
    }

    // Our own services throw Exception('readable message')
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      final msg = text.substring('Exception: '.length).trim();
      if (msg.isNotEmpty && !_looksTechnical(msg)) return msg;
    }
    final lower = text.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection')) {
      return noInternet;
    }
    return fallback;
  }

  static bool _looksTechnical(String msg) =>
      msg.contains('[') ||
      msg.contains('Null check') ||
      msg.contains('type \'') ||
      msg.contains('RangeError') ||
      msg.contains('StateError');

  static String? _auth(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email address already exists. Please log in or use a different email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters with letters and numbers.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return noInternet;
      case 'requires-recent-login':
        return 'Please log in again to continue.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';
    }
    return null;
  }

  static String? _firebase(String plugin, String code) {
    switch (code) {
      case 'unavailable':
      case 'network-request-failed':
        return noInternet;
      case 'deadline-exceeded':
      case 'retry-limit-exceeded':
        return 'The server is taking too long. Please try again.';
      case 'permission-denied':
      case 'unauthorized':
        return 'You do not have permission to do this.';
      case 'unauthenticated':
        return 'Your session has expired. Please log in again.';
      case 'not-found':
      case 'object-not-found':
        return plugin == 'firebase_storage'
            ? 'The file could not be found.'
            : 'This record no longer exists.';
      case 'already-exists':
        return 'This record already exists.';
      case 'resource-exhausted':
      case 'quota-exceeded':
        return 'The service is busy right now. Please try again shortly.';
      case 'aborted':
        return 'Someone else changed this at the same time. Please try again.';
      case 'canceled':
      case 'cancelled':
        return 'The upload was cancelled.';
      case 'invalid-checksum':
        return 'The file was damaged during upload. Please try again.';
    }
    return null;
  }

  /// App-wide messenger (set on MaterialApp) used by [showGlobal].
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static String? _lastGlobal;
  static DateTime _lastGlobalAt = DateTime(2000);

  /// Safety net for errors no screen caught (e.g. a failed tap action):
  /// shows a friendly message instead of failing silently. The same
  /// message is not repeated within 4 seconds.
  static void showGlobal(Object error) {
    final msg = of(error);
    final now = IstClock.now();
    if (msg == _lastGlobal && now.difference(_lastGlobalAt).inSeconds < 4) {
      return;
    }
    _lastGlobal = msg;
    _lastGlobalAt = now;
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.danger,
    ));
  }

  /// Shows [error] as a red snackbar, if the screen is still open.
  static void show(BuildContext context, Object error, {String? action}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(of(error, action: action)),
      backgroundColor: AppColors.danger,
    ));
  }
}

/// Shown in place of a list when its data could not be loaded.
class LoadErrorView extends StatelessWidget {
  final Object? error;
  final String what; // e.g. "your bookings"
  const LoadErrorView({super.key, this.error, required this.what});

  @override
  Widget build(BuildContext context) {
    final msg = error == null
        ? 'Could not load $what.'
        : ErrorMessages.of(error!, action: 'load $what');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.slate)),
        ],
      ),
    );
  }
}
