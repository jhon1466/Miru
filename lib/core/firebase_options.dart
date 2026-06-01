// Archivo generado con la configuración de Firebase para el proyecto serie-938f4
// Proyecto: serie-938f4 | App Android: com.jhondev146.pruebaseries

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'use FirebaseOptions directly.',
      );
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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCt8cXXc5b241BezE0JMHjIJHJt-4tkWHs',
    appId: '1:997417539791:android:100ba98c1b3f8ff65a3fba',
    messagingSenderId: '997417539791',
    projectId: 'serie-938f4',
    storageBucket: 'serie-938f4.firebasestorage.app',
  );

  // iOS: Completar cuando se tenga GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCt8cXXc5b241BezE0JMHjIJHJt-4tkWHs',
    appId: '1:997417539791:ios:placeholder',
    messagingSenderId: '997417539791',
    projectId: 'serie-938f4',
    storageBucket: 'serie-938f4.firebasestorage.app',
    iosClientId: '997417539791-4g1tcp44o7udd0cue2edp9ou60i3i9l4.apps.googleusercontent.com',
    iosBundleId: 'com.jhondev146.pruebaseries',
  );
}
