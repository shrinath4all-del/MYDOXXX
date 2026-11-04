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

class _ConnectionBannerState extends State<ConnectionBanner> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  Timer? _debounce;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_watch);
  }

  void _watch(User? user) {
    _docSub?.cancel();
    _docSub = null;
    _setOffline(false);
    if (user == null) return;
    _docSub = AppDatabase.instance
        .collection('users')
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      final fromCache = snap.metadata.isFromCache;
      _debounce?.cancel();
      if (!fromCache) {
        _setOffline(false);
      } else {
        // the first answer always comes from the saved copy: only call it
        // offline if the server still has not answered a few seconds later
        _debounce = Timer(const Duration(seconds: 6), () => _setOffline(true));
      }
    }, onError: (_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 6), () => _setOffline(true));
    });
  }

  void _setOffline(bool v) {
    if (!mounted || _offline == v) return;
    setState(() => _offline = v);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
