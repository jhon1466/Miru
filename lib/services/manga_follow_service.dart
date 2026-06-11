import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/manga.dart';
import 'manga_favorite_service.dart';
import 'tracked_series_service.dart';

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
    final topic = 'manga_${details.id}';

    if (doc.exists) {
      await ref.delete();
      final isFav = await MangaFavoriteService.isFavorite(userId, details.id);
      if (!isFav) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        } catch (e) {
          debugPrint('[MangaFollow] error al desuscribirse de $topic: $e');
        }
      }
    } else {
      await ref.set({
        'mangaId': details.id,
        'title': details.title,
        'coverUrl': details.coverUrl ?? fallbackImage,
        'status': details.status,
        'followedAt': FieldValue.serverTimestamp(),
      });
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('[MangaFollow] suscrito a FCM: $topic');
      } catch (e) {
        debugPrint('[MangaFollow] error al suscribirse a $topic: $e');
      }
      await TrackedSeriesService.registerManga(
        topic: topic,
        mangaId: details.id,
        slug: details.slug,
        title: details.title,
        image: details.coverUrl ?? fallbackImage,
      );
    }
  }
}
