// Copia este archivo como firebase_options.dart tras configurar Firebase.
// Generación recomendada: flutterfire configure --project=serie-938f4
//
// NO subas firebase_options.dart ni google-services.json a un repo público
// sin restricciones de API key en Google Cloud Console.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web no configurado.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Plataforma no soportada.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'TU_API_KEY_ANDROID',
    appId: 'TU_APP_ID_ANDROID',
    messagingSenderId: 'TU_SENDER_ID',
    projectId: 'serie-938f4',
    storageBucket: 'serie-938f4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TU_API_KEY_IOS',
    appId: 'TU_APP_ID_IOS',
    messagingSenderId: 'TU_SENDER_ID',
    projectId: 'serie-938f4',
    storageBucket: 'serie-938f4.firebasestorage.app',
    iosClientId: 'TU_IOS_CLIENT_ID',
    iosBundleId: 'com.jhondev146.pruebaseries',
  );
}
