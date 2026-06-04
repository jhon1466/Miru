import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/novel.dart';
import 'novel_favorite_service.dart';

class NovelFollowService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _followRef(String userId) {
    return _db.collection('users').doc(userId).collection('novel_following');
  }

  static String _topicName(String novelId) {
    final clean = novelId.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
    final topic = 'novel_$clean';
    return topic.length > 900 ? topic.substring(0, 900) : topic;
  }

  /// Stream en tiempo real de novelas seguidas por el usuario.
  static Stream<List<FavoriteNovel>> getFollowing(String userId) {
    return _followRef(userId)
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return FavoriteNovel(
                novelId: data['novelId'] ?? '',
                title: data['title'] ?? 'Sin Título',
                coverUrl: data['coverUrl'],
                status: data['status'],
                author: data['author'],
                addedAt: (data['followedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              );
            }).toList());
  }

  /// Stream que emite si se está siguiendo la novela.
  static Stream<bool> isFollowingStream(String userId, String novelId) {
    return _followRef(userId).doc(novelId).snapshots().map((doc) => doc.exists);
  }

  /// Verifica si se está siguiendo la novela (Future).
  static Future<bool> isFollowing(String userId, String novelId) async {
    final doc = await _followRef(userId).doc(novelId).get();
    return doc.exists;
  }

  /// Alterna seguir/dejar de seguir + suscripción/baja de FCM.
  static Future<void> toggleFollow(
    String userId,
    Novel novel,
  ) async {
    final ref = _followRef(userId).doc(novel.id);
    final doc = await ref.get();
    final topic = _topicName(novel.id);

    if (doc.exists) {
      await ref.delete();
      // Solo desuscribir si tampoco es favorito
      final isFav = await NovelFavoriteService.isFavorite(userId, novel.id);
      if (!isFav) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
          debugPrint('[NovelFollow] Desuscrito de FCM: $topic');
        } catch (e) {
          debugPrint('[NovelFollow] Error al desuscribirse de $topic: $e');
        }
      }
    } else {
      await ref.set({
        'novelId': novel.id,
        'title': novel.title,
        'coverUrl': novel.coverUrl,
        'status': novel.status,
        'author': novel.author,
        'followedAt': FieldValue.serverTimestamp(),
      });
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('[NovelFollow] Suscrito a FCM: $topic');
      } catch (e) {
        debugPrint('[NovelFollow] Error al suscribirse a $topic: $e');
      }
    }
  }
}
