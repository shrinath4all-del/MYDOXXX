import '../services/app_database.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Shows a small "No internet" pill at the top of the app whenever live data
/// can't reach the server, so nobody trusts a frozen emergency status or
/// request list. It watches the signed-in user's own document: Firestore
/// marks it "from cache" while the server is unreachable.
class ConnectionBanner extends StatefulWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  Timer? _debounce;
  Timer? _recheck;
  bool _offline = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_watch);
  }

  /// Back from the background (another tab, another app, screen off): the
  /// browser or phone may have dropped the live connection, so listen again
  /// and only warn if the server really cannot be reached.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _watch(FirebaseAuth.instance.currentUser);
    }
  }

  void _watch(User? user) {
    _docSub?.cancel();
    _docSub = null;
    _debounce?.cancel();
    _recheck?.cancel();
    _setOffline(false);
    if (user == null) return;
    _docSub = AppDatabase.instance
        .collection('users')
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      _debounce?.cancel();
      if (!snap.metadata.isFromCache) {
        _recheck?.cancel();
        _setOffline(false);
      } else {
        // the first answer (and the one after coming back) comes from the
        // saved copy: ask the server before calling it offline
        _debounce = Timer(const Duration(seconds: 8), _confirm);
      }
    }, onError: (_) {
      // a failed listener stops for good: start a new one, then check
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        _watch(FirebaseAuth.instance.currentUser);
        _confirm();
      });
    });
  }

  /// Asks the server directly. Offline only when it cannot be reached; the
  /// check repeats every few seconds so the pill goes away by itself.
  Future<void> _confirm() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _checking || !mounted) return;
    _checking = true;
    bool reached;
    try {
      await AppDatabase.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      reached = true;
    } on FirebaseException catch (e) {
      // the server answered (even "not allowed"): the internet works
      reached = e.code != 'unavailable' && e.code != 'deadline-exceeded';
    } catch (_) {
      reached = false; // timed out
    } finally {
      _checking = false;
    }
    if (!mounted) return;
    _setOffline(!reached);
    _recheck?.cancel();
    if (!reached) _recheck = Timer(const Duration(seconds: 10), _confirm);
  }

  void _setOffline(bool v) {
    if (!mounted || _offline == v) return;
    setState(() => _offline = v);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _recheck?.cancel();
    _docSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        widget.child,
        if (_offline)
          Positioned(
            top: top + 6,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Material(
                  color: AppColors.danger,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'No internet · showing saved data',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
