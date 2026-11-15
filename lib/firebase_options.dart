// Firebase project nasa-4225d. Generated from android/app/google-services.json
// and ios/Runner/GoogleService-Info.plist (what `flutterfire configure` writes).
// Client config, not a secret: the keys are restricted to these app IDs.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  /// Null where Firebase is not set up (web, desktop): push is then off.
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => null,
    };
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyC42sioy3A7BL7vltdymDLMmn84SHAxeJY',
    appId: '1:835948546488:android:2bdd92775b3c708ed6e74d',
    messagingSenderId: '835948546488',
    projectId: 'nasa-4225d',
    storageBucket: 'nasa-4225d.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBNbPhqD8QyPnXaUN3noBulejE14o7pVow',
    appId: '1:835948546488:ios:5c6962491b9be8b1d6e74d',
    messagingSenderId: '835948546488',
    projectId: 'nasa-4225d',
    storageBucket: 'nasa-4225d.firebasestorage.app',
    iosBundleId: 'online.codingnow.firesight',
  );
}
