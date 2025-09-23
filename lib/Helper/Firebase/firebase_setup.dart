// File: lib/firebase_options.dart

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // 👉 You don’t have web config yet, keep placeholders
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD__9QHHjtXsbFJs9R6bwrKY1bGjZ3fKxU',
    appId: '1:53810020944:android:253fc3d7df084c25fb0755',
    messagingSenderId: '53810020944',
    projectId: 'habit-tracker-cc8f8',
    authDomain: 'habit-tracker-cc8f8.firebaseapp.com',
    storageBucket: 'habit-tracker-cc8f8.firebasestorage.app',
    measurementId: 'YOUR_MEASUREMENT_ID',
  );

  // ✅ Android values filled from google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD__9QHHjtXsbFJs9R6bwrKY1bGjZ3fKxU',
    appId: '1:53810020944:android:253fc3d7df084c25fb0755',
    messagingSenderId: '53810020944',
    authDomain: "habit-tracker-cc8f8.firebaseapp.com",
    projectId: 'habit-tracker-cc8f8',
    storageBucket: 'habit-tracker-cc8f8.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: '53810020944',
    projectId: 'habit-tracker-cc8f8',
    iosBundleId: 'com.example.app',
    storageBucket: 'habit-tracker-cc8f8.firebasestorage.app',
  );
}
