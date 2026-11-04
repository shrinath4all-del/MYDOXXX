// MYDOXXX configuration from its independent Firebase app registrations.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        throw UnsupportedError('MYDOXXX desktop setup is pending.');
      default:
        throw UnsupportedError(
            'MYDOXXX Firebase is not configured on this platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyALlnQksw2ZzXlFqf8Myqzs2nnwu78qZ7I',
    appId: '1:724915428929:web:ce9c0a4ab47a83e70d70c0',
    messagingSenderId: '724915428929',
    projectId: 'mydoxxx-dev-261102',
    authDomain: 'mydoxxx-dev-261102.firebaseapp.com',
    storageBucket: 'mydoxxx-dev-261102.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOr7HOK3cuCoroGwufqIRGbYcdJyr4AHk',
    appId: '1:724915428929:android:39f9436760e8b9c50d70c0',
    messagingSenderId: '724915428929',
    projectId: 'mydoxxx-dev-261102',
    storageBucket: 'mydoxxx-dev-261102.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBhvmCuSvAGZZpOOiu2CzV8arADTs6_WvI',
    appId: '1:724915428929:ios:50d15b209b9cf7a90d70c0',
    messagingSenderId: '724915428929',
    projectId: 'mydoxxx-dev-261102',
    storageBucket: 'mydoxxx-dev-261102.firebasestorage.app',
    iosBundleId: 'com.mydox.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBhvmCuSvAGZZpOOiu2CzV8arADTs6_WvI',
    appId: '1:724915428929:ios:50d15b209b9cf7a90d70c0',
    messagingSenderId: '724915428929',
    projectId: 'mydoxxx-dev-261102',
    storageBucket: 'mydoxxx-dev-261102.firebasestorage.app',
    iosBundleId: 'com.mydox.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyALlnQksw2ZzXlFqf8Myqzs2nnwu78qZ7I',
    appId: '1:724915428929:web:06c101389fdffc620d70c0',
    messagingSenderId: '724915428929',
    projectId: 'mydoxxx-dev-261102',
    authDomain: 'mydoxxx-dev-261102.firebaseapp.com',
    storageBucket: 'mydoxxx-dev-261102.firebasestorage.app',
  );
}
