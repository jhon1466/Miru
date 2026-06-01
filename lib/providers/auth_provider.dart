import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import '../services/user_service.dart';
import '../services/push_notification_service.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ImagePicker _imagePicker = ImagePicker();

  User? _user;
  String? _pendingWelcomeName;

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;
  String? get userId => _user?.uid;
  String? get displayName => _user?.displayName;
  String? get photoUrl => _user?.photoURL;
  String? get email => _user?.email;

  AuthProvider() {
    _user = _auth.currentUser;
    _auth.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  /// Inicia sesión con Google. Devuelve el nombre para mensaje de bienvenida, o null si canceló/falló.
  Future<String?> signInWithGoogle() async {
    try {
      final googleAccount = await _googleSignIn.signIn();
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      _user = userCredential.user;

      if (_user != null) {
        await UserService.createOrUpdateProfile(
          uid: _user!.uid,
          displayName: _user!.displayName ?? 'Usuario',
          photoUrl: _user!.photoURL,
          email: _user!.email,
        );
        await PushNotificationService.registerTokenForUser(_user!.uid);
      }

      final welcomeName = _user?.displayName ?? _user?.email?.split('@').first ?? 'Usuario';
      _pendingWelcomeName = welcomeName;
      notifyListeners();
      return welcomeName;
    } catch (e) {
      debugPrint('Error en Google Sign-In: $e');
      return null;
    }
  }

  String? consumeWelcomeName() {
    final name = _pendingWelcomeName;
    _pendingWelcomeName = null;
    return name;
  }

  Future<void> signOut() async {
    final uid = _user?.uid;
    if (uid != null) {
      await PushNotificationService.unregisterCurrentToken(uid);
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
    _user = null;
    _pendingWelcomeName = null;
    notifyListeners();
  }

  /// Sube foto de perfil a Storage y actualiza Auth + Firestore.
  Future<String?> updateProfilePhotoFromGallery() async {
    if (_user == null) return null;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return null;

      final file = File(picked.path);
      final uid = _user!.uid;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child('profile.jpg');

      await storageRef.putFile(
        file,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'owner': uid},
        ),
      );
      final downloadUrl = await storageRef.getDownloadURL();

      await _user!.updatePhotoURL(downloadUrl);
      await UserService.updatePhotoUrl(uid, downloadUrl);
      await _user!.reload();
      _user = _auth.currentUser;
      notifyListeners();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error al actualizar foto de perfil: $e');
      rethrow;
    }
  }

  /// Actualiza el nombre visible en Auth, Firestore y comentarios previos.
  Future<void> updateDisplayName(String displayName) async {
    if (_user == null) return;
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;

    await _user!.updateDisplayName(trimmed);
    await UserService.updateDisplayName(_user!.uid, trimmed);
    await _user!.reload();
    _user = _auth.currentUser;
    notifyListeners();
  }
}
