import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/user_service.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? _user;

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;
  String? get userId => _user?.uid;
  String? get displayName => _user?.displayName;
  String? get photoUrl => _user?.photoURL;
  String? get email => _user?.email;

  AuthProvider() {
    // Escuchar cambios de estado de autenticación
    _auth.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  /// Inicia sesión con Google y registra/actualiza el usuario en Firebase Auth y Firestore.
  Future<bool> signInWithGoogle() async {
    try {
      // Forzar selector de cuenta de Google
      final googleAccount = await _googleSignIn.signIn();
      if (googleAccount == null) return false; // El usuario canceló

      final googleAuth = await googleAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      _user = userCredential.user;

      // Crear o actualizar perfil en Firestore
      if (_user != null) {
        await UserService.createOrUpdateProfile(
          uid: _user!.uid,
          displayName: _user!.displayName ?? 'Usuario',
          photoUrl: _user!.photoURL,
          email: _user!.email,
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error en Google Sign-In: $e');
      return false;
    }
  }

  /// Cierra la sesión de Firebase y de Google.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }
}

