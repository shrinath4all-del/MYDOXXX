import '../services/app_database.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../services/push_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/error_messages.dart';
import '../services/session_service.dart';
import '../constants/app_colors.dart';

/// Key of the app's root Navigator (set on MaterialApp).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Wraps the whole app. For every role (patient, doctor, hospital, ambulance,
/// nurse, technician, therapist, care physician, agency, admin) it keeps a
/// single active session per account: when the same account signs in on
/// another device, this device is signed out and taken to the login screen.
class SessionGuard extends StatefulWidget {
  final Widget child;
  const SessionGuard({super.key, required this.child});

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  String? _uid;
  bool _kicking = false;

  Timer? _chatTimer;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    // A tapped chat notification opens that chat. On a cold start it waits
    // until the home screen is up (the splash would otherwise replace it).
    PushService.chatSignal.addListener(_tryOpenChat);
    SessionService.recheck.addListener(_recheck);
    // cold start from a chat notification: open it once the app is ready
    _tryOpenChat();
  }

  bool _openingChat = false;

  /// While a tapped chat waits for the app (splash / login), check again
  /// shortly; no timer runs when nothing is waiting.
  void _retryChatSoon() {
    if (_chatTimer?.isActive ?? false) return;
    _chatTimer = Timer(const Duration(milliseconds: 600), _tryOpenChat);
  }

  Future<void> _tryOpenChat() async {
    final chat = PushService.pendingChat;
    if (chat == null || _openingChat) return;
    final user = FirebaseAuth.instance.currentUser;
    final nav = rootNavigatorKey.currentState;
    if (!SessionService.appReady || user == null || nav == null) {
      if (mounted) _retryChatSoon();
      return;
    }
    _openingChat = true;
    PushService.pendingChat = null;
    try {
      final chatId = chat['chatId'] ?? '';
      // only a participant may open it
      final parts = chatId.split('_');
      if (!parts.contains(user.uid)) return;
      // ambulance chat: the chat screen shows whether the ambulance is on duty
      final chatDoc = (await AppDatabase.instance
              .collection('chats')
              .doc(chatId)
              .get())
          .data();
      final sosId = chatDoc?['ambulanceSosId'];
      // a notification can outlive the chat window: the same rule as the
      // Chat button applies (opens when the consultation starts, closes 24 h
      // after it)
      if (sosId is! String &&
          parts.length == 2 &&
          !await FirestoreService.chatAllowedBetween(parts[0], parts[1])) {
        ErrorMessages.messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Chat is closed for this booking.')));
        return;
      }
      final me = (await AppDatabase.instance.collection('users').doc(user.uid).get()).data();
      final roleLabel = (chat['senderRole'] ?? '').isNotEmpty ? chat['senderRole']! : 'Patient';
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          currentUserId: user.uid,
          currentUserName: (me?['name'] ?? '').toString(),
          peerName: (chat['senderName'] ?? '').isNotEmpty ? chat['senderName']! : 'Chat',
          peerRole: roleLabel,
          ambulanceSosId: sosId is String ? sosId : null,
          allowVideo: sosId is! String,
        ),
      ));
    } finally {
      _openingChat = false;
    }
  }

  @override
  void dispose() {
    PushService.chatSignal.removeListener(_tryOpenChat);
    SessionService.recheck.removeListener(_recheck);
    _chatTimer?.cancel();
    _authSub?.cancel();
    _docSub?.cancel();
    super.dispose();
  }

  void _onAuth(User? user) {
    _docSub?.cancel();
    _docSub = null;
    _uid = user?.uid;
    if (user == null) {
      _kicking = false;
      return;
    }
    _docSub = AppDatabase.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(_onAccount, onError: (_) {});
  }

  Future<void> _onAccount(DocumentSnapshot<Map<String, dynamic>> snap) async {
    if (_uid == null || _kicking || SessionService.paused) return;
    // a stale cached copy can't prove another device signed in
    if (snap.metadata.hasPendingWrites) return;
    await _check(snap.data());
  }

  /// Login (or sign-out) just finished: snapshots that came in meanwhile were
  /// skipped, so compare with the server's copy now.
  Future<void> _recheck() async {
    final uid = _uid;
    if (uid == null || _kicking || SessionService.paused) return;
    try {
      final snap = await AppDatabase.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (_uid != uid || _kicking || SessionService.paused) return;
      await _check(snap.data());
    } catch (_) {
      // offline: the live listener checks as soon as it can
    }
  }

  Future<void> _check(Map<String, dynamic>? data) async {
    final uid = _uid;
    if (uid == null) return;
    final remote = (data?['sessionId'] ?? '').toString();
    final remoteDevice = (data?['sessionDevice'] ?? '').toString();
    final local = await SessionService.localId(uid);

    if (remote.isEmpty) {
      // Nobody has claimed this account yet (signed in before this feature
      // or just registered): this device becomes the active session.
      if (local == null || local.isEmpty) {
        await SessionService.claim(uid);
      } else {
        await SessionService.publish(uid, local);
      }
      return;
    }
    if (local == null || local.isEmpty) {
      // This device is signed in but lost its saved id (cleared cache, a
      // restored backup). That is not another device signing in: if the
      // account's session was last on this same kind of device, keep this
      // one signed in and save a new id.
      if (remoteDevice == SessionService.deviceLabel) {
        await SessionService.claim(uid);
        return;
      }
    }
    if (local != remote) await _signedOutElsewhere();
  }

  Future<void> _signedOutElsewhere() async {
    if (_kicking) return;
    _kicking = true;
    final uid = _uid;
    try {
      await AuthService().signOut();
    } catch (_) {}
    await SessionService.clearLocal(uid);

    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    // show the reason once the login screen is up
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      showDialog<void>(
        context: ctx,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.devices_other_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(child: Text('Signed out')),
            ],
          ),
          content: const Text(
            'You were signed out because your account was signed in on another device. '
            'Only one device can be signed in to an account at a time.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
