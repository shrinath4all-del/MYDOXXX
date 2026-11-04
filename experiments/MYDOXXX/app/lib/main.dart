import 'config/test_lab_config.dart';
import 'screens/test_lab/test_lab_login_screen.dart';
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'config/experiment_environment.dart';
import 'screens/splash_screen.dart';
import 'services/images_master.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'utils/error_messages.dart';
import 'utils/responsive.dart';
import 'widgets/connection_banner.dart';
import 'widgets/session_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (TestLabConfig.enabled) TestLabConfig.requireLocal(Uri.base);
  final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
  ExperimentEnvironment.validateProject(firebaseOptions.projectId);
  await Firebase.initializeApp(options: firebaseOptions);
  // Web: keep the login per browser tab, so one browser can hold an admin in
  // one window and an agency in another. By default every tab of a browser
  // shares one login, and signing in on a second tab switches (or signs out)
  // the first. The login still survives a reload; it ends when the tab closes.
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(
        TestLabConfig.enabled ? Persistence.NONE : Persistence.SESSION);
  }
  // Push messages exist on the web, Android and iOS (not on Windows)
  if (ExperimentEnvironment.externalActionsEnabled &&
      (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  // Errors no screen handled (e.g. a button whose save failed offline):
  // tell the user instead of failing silently.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error');
    if (kDebugMode) debugPrintStack(stackTrace: stack);
    ErrorMessages.showGlobal(error);
    return true;
  };
  // pictures load while the splash and login show
  if (!TestLabConfig.enabled) ImagesMaster.warmUp();
  runApp(const MyDoxApp());
}

class MyDoxApp extends StatelessWidget {
  const MyDoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MYDOXXX Experiment',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const _AppScrollBehavior(),
      scaffoldMessengerKey: ErrorMessages.messengerKey,
      // Very large system font sizes would push text out of cards and
      // buttons: the user's setting, adjusted to the screen width, stays
      // within 85â€“130%
      builder: (context, child) {
        final content = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: Responsive.appTextScaler(MediaQuery.of(context)),
          ),
          child: TestLabConfig.enabled
              ? TestLabBanner(
                  child:
                      ConnectionBanner(child: child ?? const SizedBox.shrink()))
              : ConnectionBanner(child: child ?? const SizedBox.shrink()),
        );
        return TestLabConfig.enabled ? content : SessionGuard(child: content);
      },
      home: TestLabConfig.enabled
          ? const TestLabLoginScreen()
          : const SplashScreen(),
    );
  }
}

/// Lets horizontal rows (tabs, chips, filters) be dragged with a mouse or
/// trackpad too, so they scroll on web/desktop the same as on phones.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
