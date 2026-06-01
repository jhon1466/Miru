import 'package:cloud_firestore/cloud_firestore.dart';

/// Datos del perfil de usuario en Firestore (/users/{uid})
class UserProfile {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? email;
  final bool isPublic; // Si el perfil y favoritos son visibles para todos
  final DateTime? createdAt;

  UserProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.email,
    this.isPublic = true,
    this.createdAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Usuario',
      photoUrl: data['photoUrl'],
      email: data['email'],
      isPublic: data['isPublic'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'photoUrl': photoUrl,
      'email': email,
      'isPublic': isPublic,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? email,
    bool? isPublic,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      email: email ?? this.email,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
    );
  }
}

class UserService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference _userRef(String uid) =>
      _db.collection('users').doc(uid);

  /// Crea o actualiza el documento del perfil del usuario en Firestore.
  /// Usualmente llamado al hacer Sign-In.
  static Future<void> createOrUpdateProfile({
    required String uid,
    required String displayName,
    String? photoUrl,
    String? email,
  }) async {
    final ref = _userRef(uid);
    final doc = await ref.get();
    if (!doc.exists) {
      // Crear perfil por primera vez
      final profile = UserProfile(
        uid: uid,
        displayName: displayName,
        photoUrl: photoUrl,
        email: email,
        isPublic: true,
        createdAt: DateTime.now(),
      );
      await ref.set(profile.toFirestore());
    } else {
      // Actualizar solo campos que pueden cambiar (nombre de cuenta, foto)
      await ref.update({
        'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (email != null) 'email': email,
      });
    }
  }

  /// Obtiene el perfil de un usuario por su UID.
  static Future<UserProfile?> getProfile(String uid) async {
    final doc = await _userRef(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  /// Stream en tiempo real del perfil del usuario actual.
  static Stream<UserProfile?> profileStream(String uid) {
    return _userRef(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  /// Actualiza la privacidad del perfil del usuario.
  static Future<void> setProfilePublic(String uid, bool isPublic) async {
    await _userRef(uid).update({'isPublic': isPublic});
  }
}
