import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/manga.dart';
import 'manga_favorite_service.dart';

class MangaFollowService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _followRef(String userId) {
    return _db.collection('users').doc(userId).collection('manga_following');
  }

  /// Stream en tiempo real de los mangas seguidos por el usuario.
  static Stream<List<FavoriteManga>> getFollowing(String userId) {
    return _followRef(userId)
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return FavoriteManga(
                mangaId: data['mangaId'] ?? '',
                title: data['title'] ?? 'Sin Título',
                coverUrl: data['coverUrl'],
                status: data['status'],
                addedAt: (data['followedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              );
            }).toList());
  }

  /// Verifica si un manga se está siguiendo (Stream).
  static Stream<bool> isFollowingStream(String userId, String mangaId) {
    return _followRef(userId).doc(mangaId).snapshots().map((doc) => doc.exists);
  }

  /// Verifica si un manga se está siguiendo (Future).
  static Future<bool> isFollowing(String userId, String mangaId) async {
    final doc = await _followRef(userId).doc(mangaId).get();
    return doc.exists;
  }

  /// Alterna seguir manga.
  static Future<void> toggleFollow(
    String userId,
    Manga details, {
    String? fallbackImage,
  }) async {
    final ref = _followRef(userId).doc(details.id);
    final doc = await ref.get();

    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set({
        'mangaId': details.id,
        'title': details.title,
        'coverUrl': details.coverUrl ?? fallbackImage,
        'status': details.status,
        'followedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
