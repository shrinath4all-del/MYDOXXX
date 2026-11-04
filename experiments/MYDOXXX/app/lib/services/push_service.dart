import 'app_database.dart';
import '../config/experiment_environment.dart';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'presence_service.dart';

const AndroidNotificationChannel _callChannel = AndroidNotificationChannel(
  'incoming_calls',
  'Incoming video calls',
  description: 'Rings when a doctor or patient video-calls you',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const AndroidNotificationChannel _alertChannel = AndroidNotificationChannel(
  'emergency_alerts',
  'Requests & updates',
  description: 'New requests, emergency alerts and status updates',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

Future<void> _initLocal() async {
  await _local.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
    // Tapping a notification we showed ourselves (app was open)
    onDidReceiveNotificationResponse: (r) {
      // payload = the push's data as JSON (see _showForeground)
      try {
        final data = Map<String, dynamic>.from(jsonDecode(r.payload ?? '{}') as Map);
        PushService.notificationTapped(data['type']?.toString(), data);
      } catch (_) {
        PushService.notificationTapped(r.payload);
      }
    },
  );
  await _local
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_callChannel);
  await _local
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_alertChannel);

  // The app was opened from closed by tapping a notification we showed
  // ourselves (it waited in the tray): the plain push path (getInitialMessage)
  // does not know about those. Handled once per app start.
  if (!_launchHandled) {
    _launchHandled = true;
    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && r != null) {
        try {
          final data =
              Map<String, dynamic>.from(jsonDecode(r.payload ?? '{}') as Map);
          PushService.notificationTapped(data['type']?.toString(), data);
        } catch (_) {
          PushService.notificationTapped(r.payload);
        }
      }
    } catch (_) {}
  }
}

bool _launchHandled = false;

Future<void> _showCallNotification(Map<String, dynamic> data) async {
  if (data['type'] != 'incoming_call') return;
  // On iOS the system already shows the push alert sent with the message.
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final caller = (data['callerName'] ?? 'Someone').toString();
  final audio = data['audioOnly'] == 'true';
  await _local.show(
    // one slot per call so a new call replaces the old ring
    9001,
    audio ? 'Incoming audio call' : 'Incoming video call',
    '$caller is calling youâ€¦',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _callChannel.id,
        _callChannel.name,
        channelDescription: _callChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true, // wakes the screen like a real call
        ongoing: true,
        autoCancel: true,
        timeoutAfter: 45000, // stops ringing when the call times out
        visibility: NotificationVisibility.public,
      ),
    ),
  );
}

/// Runs in its own isolate while the app is in the background / closed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!ExperimentEnvironment.externalActionsEnabled) return;
  await _initLocal();
  await _showCallNotification(message.data);
}

Future<void> _showForeground(RemoteMessage message) async {
  if (message.data['type'] == 'incoming_call') return;
  final n = message.notification;
  if (n == null || defaultTargetPlatform != TargetPlatform.android) return;
  // already reading this chat: no banner for its own messages
  if (message.data['type'] == 'chat' &&
      message.data['chatId'] == PushService.activeChatId) {
    return;
  }
  await _local.show(
    message.messageId.hashCode,
    n.title,
    n.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannel.id,
        _alertChannel.name,
        channelDescription: _alertChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

class PushService {
  static bool _listening = false;

  /// A notification was tapped: the bell in the patient / doctor home opens
  /// the notifications list. [pendingOpen] covers a cold start, before the
  /// home screen exists.
  static final ValueNotifier<int> openSignal = ValueNotifier<int>(0);
  static bool pendingOpen = false;

  /// Chat id of the chat screen that is open right now (no banners for it).
  static String? activeChatId;

  /// A chat notification was tapped: the app opens that chat (see
  /// SessionGuard). Kept until the home screen is ready (cold start).
  static Map<String, String>? pendingChat;
  static final ValueNotifier<int> chatSignal = ValueNotifier<int>(0);

  static void notificationTapped(String? type, [Map<String, dynamic>? data]) {
    if (type == 'incoming_call') return; // the ringing screen handles calls
    if (type == 'chat' && data != null && data['chatId'] != null) {
      pendingChat = {
        for (final e in data.entries) e.key: e.value.toString(),
      };
      chatSignal.value++;
      return;
    }
    pendingOpen = true;
    openSignal.value++;
  }

  /// Call once after sign-in: asks for notification permission, stores this
  /// device's FCM token on the user's document and shows call notifications.
  static Future<void> registerForUser(String uid) async {
    if (!ExperimentEnvironment.externalActionsEnabled) return;
    PresenceService.start(uid); // "Online" in chats
    if (kIsWeb) return;
    // phone notifications exist on Android and iOS only (not on Windows)
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await _initLocal();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, sound: true, badge: true);
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final token = await messaging.getToken();
      if (token != null) await _saveToken(uid, token);
      // only the signed-in account follows token refreshes (the previous
      // account's listener used to re-add the new token to the old account)
      await _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));

      if (!_listening) {
        _listening = true;
        // iPhone: also show pushes while the app is open
        await messaging.setForegroundNotificationPresentationOptions(
            alert: true, badge: true, sound: true);
        // Android does NOT show a push while the app is open on screen, it
        // only hands it to the app. Show it ourselves as a heads-up
        // notification (calls are handled by the in-app ringing screen).
        FirebaseMessaging.onMessage.listen(_showForeground);

        // Tapped a push in the phone's notification panel while the app was
        // in the background...
        FirebaseMessaging.onMessageOpenedApp
            .listen((m) => notificationTapped(m.data['type']?.toString(), m.data));
        // ...or closed (the tap launched the app)
        final initial = await messaging.getInitialMessage();
        if (initial != null) {
          notificationTapped(initial.data['type']?.toString(), initial.data);
        }
      }
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  static StreamSubscription<String>? _refreshSub;

  /// One phone notifies one account: the token is added to [uid] and taken
  /// off any other account that still has it (e.g. a patient who was signed
  /// in on this phone before a doctor signed in).
  static Future<void> _saveToken(String uid, String token) async {
    final users = AppDatabase.instance.collection('users');
    await users.doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
    try {
      final others =
          await users.where('fcmTokens', arrayContains: token).get();
      for (final d in others.docs) {
        if (d.id == uid) continue;
        await d.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
    } catch (e) {
      // best effort (a rule may not allow the lookup); sign-in goes on
      debugPrint('Push token cleanup skipped: $e');
    }
  }

  /// Call on sign-out so this device stops ringing for the old account:
  /// the token is removed from it and then deleted, so a copy left on any
  /// account can no longer deliver to this phone.
  static Future<void> unregisterForUser(String uid) async {
    PresenceService.stop();
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) {
        await AppDatabase.instance.collection('users').doc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
      await messaging.deleteToken();
    } catch (_) {}
  }
}
