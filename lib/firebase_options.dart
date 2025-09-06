// Firebase configuration for Mono Android app
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCYRyOs8i861Ot3uCQJd8YoGW0lCokn9Ak',
    appId: '1:451747116331:android:4a97e49475cc76f323416e',
    messagingSenderId: '451747116331',
    projectId: 'mono-moments',
    storageBucket: 'mono-moments.firebasestorage.app',
  );

}