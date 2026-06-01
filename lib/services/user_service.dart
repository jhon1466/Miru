import 'package:cloud_firestore/cloud_firestore.dart';
import 'comment_service.dart';

/// Datos del perfil de usuario en Firestore (/users/{uid})
class UserProfile {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? email;
  final bool isPublic;
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
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final isPublicRaw = data['isPublic'];
    final isPublic = isPublicRaw is bool
        ? isPublicRaw
        : (isPublicRaw?.toString().toLowerCase() != 'false');

    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Usuario',
      photoUrl: data['photoUrl']?.toString(),
      email: data['email']?.toString(),
      isPublic: isPublic,
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

  static DocumentReference _userRef(String uid) => _db.collection('users').doc(uid);

  static Future<void> createOrUpdateProfile({
    required String uid,
    required String displayName,
    String? photoUrl,
    String? email,
  }) async {
    final ref = _userRef(uid);
    final doc = await ref.get();
    if (!doc.exists) {
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
      await ref.set(
        {
          'displayName': displayName,
          if (photoUrl != null) 'photoUrl': photoUrl,
          if (email != null) 'email': email,
        },
        SetOptions(merge: true),
      );
      await _syncCommentsAuthor(uid, displayName, photoUrl);
    }
  }

  static Future<void> _syncCommentsAuthor(String uid, String displayName, String? photoUrl) async {
    try {
      await CommentService.syncAuthorProfile(
        uid: uid,
        displayName: displayName,
        photoUrl: photoUrl,
      );
    } catch (_) {
      // Índices de collection group pueden estar propagándose; la UI usa perfil en vivo.
    }
  }

  static Future<UserProfile?> getProfile(String uid) async {
    final doc = await _userRef(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  static Stream<UserProfile?> profileStream(String uid) {
    return _userRef(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  /// Actualiza privacidad del perfil (merge para no fallar si faltan campos).
  static Future<void> setProfilePublic(String uid, bool isPublic) async {
    final ref = _userRef(uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'displayName': 'Usuario',
        'isPublic': isPublic,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    await ref.set({'isPublic': isPublic}, SetOptions(merge: true));
  }

  static Future<void> updatePhotoUrl(String uid, String photoUrl) async {
    final profile = await getProfile(uid);
    final name = profile?.displayName ?? 'Usuario';
    await _userRef(uid).set({'photoUrl': photoUrl}, SetOptions(merge: true));
    await _syncCommentsAuthor(uid, name, photoUrl);
  }

  static Future<void> addFcmToken(String uid, String token) async {
    await _userRef(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  static Future<void> removeFcmToken(String uid, String token) async {
    await _userRef(uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true));
  }

  static Future<void> updateDisplayName(String uid, String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;
    final profile = await getProfile(uid);
    await _userRef(uid).set({'displayName': trimmed}, SetOptions(merge: true));
    await _syncCommentsAuthor(uid, trimmed, profile?.photoUrl);
  }
}
