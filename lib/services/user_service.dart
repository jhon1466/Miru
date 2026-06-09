import 'package:cloud_firestore/cloud_firestore.dart';
import 'comment_service.dart';

/// Datos del perfil de usuario en Firestore (/users/{uid})
class UserProfile {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? bannerUrl;
  /// Alineación vertical del banner: -1.0 arriba, 0.0 centro, 1.0 abajo
  final double bannerAlignY;
  final String? email;
  final bool isPublic;
  final bool isSupporter;
  final bool isAdmin;
  final DateTime? createdAt;

  UserProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.bannerUrl,
    this.bannerAlignY = 0.0,
    this.email,
    this.isPublic = true,
    this.isSupporter = false,
    this.isAdmin = false,
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
      bannerUrl: data['bannerUrl']?.toString(),
      bannerAlignY: (data['bannerAlignY'] as num?)?.toDouble() ?? 0.0,
      email: data['email']?.toString(),
      isPublic: isPublic,
      isSupporter: data['isSupporter'] == true,
      isAdmin: data['isAdmin'] == true,
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
    String? bannerUrl,
    double? bannerAlignY,
    String? email,
    bool? isPublic,
    bool? isSupporter,
    bool? isAdmin,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      bannerAlignY: bannerAlignY ?? this.bannerAlignY,
      email: email ?? this.email,
      isPublic: isPublic ?? this.isPublic,
      isSupporter: isSupporter ?? this.isSupporter,
      isAdmin: isAdmin ?? this.isAdmin,
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

  static Future<bool> _isAdminUid(String uid) async {
    // 1. docId == uid
    final doc = await _db.collection('admins').doc(uid).get();
    if (doc.exists) return true;
    // 2. campo uid == uid (estructura web)
    final q = await _db.collection('admins').where('uid', isEqualTo: uid).limit(1).get();
    return q.docs.isNotEmpty;
  }

  static Future<UserProfile?> getProfile(String uid) async {
    final results = await Future.wait([
      _userRef(uid).get(),
      _isAdminUid(uid),
    ]);
    final doc = results[0] as DocumentSnapshot;
    if (!doc.exists) return null;
    final isAdmin = results[1] as bool;
    final profile = UserProfile.fromFirestore(doc);
    return isAdmin ? profile.copyWith(isAdmin: true) : profile;
  }

  static Stream<UserProfile?> profileStream(String uid) {
    return _userRef(uid).snapshots().asyncMap((doc) async {
      if (!doc.exists) return null;
      bool isAdmin = false;
      try {
        isAdmin = await _isAdminUid(uid);
      } catch (_) {}
      final profile = UserProfile.fromFirestore(doc);
      return isAdmin ? profile.copyWith(isAdmin: true) : profile;
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

  static Future<void> updateBannerUrl(String uid, String? bannerUrl) async {
    if (bannerUrl != null) {
      await _userRef(uid).set({'bannerUrl': bannerUrl}, SetOptions(merge: true));
    } else {
      await _userRef(uid).update({'bannerUrl': FieldValue.delete()});
    }
  }

  static Future<void> updateBannerUrlAndAlign(String uid, String bannerUrl, double alignY) async {
    await _userRef(uid).set({
      'bannerUrl': bannerUrl,
      'bannerAlignY': alignY,
    }, SetOptions(merge: true));
  }

  static Future<void> updateBannerAlign(String uid, double alignY) async {
    await _userRef(uid).set({'bannerAlignY': alignY}, SetOptions(merge: true));
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
