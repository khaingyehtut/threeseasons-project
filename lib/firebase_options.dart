// IMPORTANT: Replace this file with your actual Firebase configuration.
// Run: flutterfire configure
// Then replace this file with the generated firebase_options.dart
//
// For now this is a placeholder so the project compiles.
// You MUST run: flutter pub global activate flutterfire_cli
//               flutterfire configure
// to generate the real file before running the app.

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
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB6W5xNuHSqRpC6JMYS2hhvk6Qt28tAF5E',
    appId: '1:751030563947:web:2f26b05ce47aab6f9aed2e',
    messagingSenderId: '751030563947',
    projectId: 'ecommerce-project-32c41',
    authDomain: 'ecommerce-project-32c41.firebaseapp.com',
    storageBucket: 'ecommerce-project-32c41.firebasestorage.app',
  );

  // TODO: Replace with your actual Firebase project values

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCo0zSwaM_M3IHscq-VhAU4j2V-Yjx_Sx4',
    appId: '1:751030563947:android:a82f44b9ad9e3df09aed2e',
    messagingSenderId: '751030563947',
    projectId: 'ecommerce-project-32c41',
    storageBucket: 'ecommerce-project-32c41.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAe_i4TTvnnN4IX1oAOJuHcrMnuX4P57S4',
    appId: '1:751030563947:ios:608cf27b783a848a9aed2e',
    messagingSenderId: '751030563947',
    projectId: 'ecommerce-project-32c41',
    storageBucket: 'ecommerce-project-32c41.firebasestorage.app',
    iosBundleId: 'com.example.threeSeasonsProject',
  );

}