import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/novel.dart';
import 'tracked_series_service.dart';

/// Modelo ligero para un favorito de novela.
class FavoriteNovel {
  final String novelId;
  final String title;
  final String? coverUrl;
  final String? status;
  final String? author;
  final DateTime addedAt;

  FavoriteNovel({
    required this.novelId,
    required this.title,
    this.coverUrl,
    this.status,
    this.author,
    required this.addedAt,
  });

  factory FavoriteNovel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoriteNovel(
      novelId: data['novelId'] ?? '',
      title: data['title'] ?? 'Sin Título',
      coverUrl: data['coverUrl'],
      status: data['status'],
      author: data['author'],
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'novelId': novelId,
      'title': title,
      'coverUrl': coverUrl,
      'status': status,
      'author': author,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }
}

class NovelFavoriteService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _favRef(String userId) {
    return _db.collection('users').doc(userId).collection('novel_favorites');
  }

  /// Genera un topic FCM limpio para la novela.
  static String _topicName(String novelId) {
    final clean = novelId.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
    final topic = 'novel_$clean';
    return topic.length > 900 ? topic.substring(0, 900) : topic;
  }

  /// Stream en tiempo real de novelas favoritas del usuario.
  static Stream<List<FavoriteNovel>> getFavorites(String userId) {
    return _favRef(userId)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FavoriteNovel.fromFirestore(doc)).toList());
  }

  /// Stream que emite si la novela está en favoritos.
  static Stream<bool> isFavoriteStream(String userId, String novelId) {
    return _favRef(userId).doc(novelId).snapshots().map((doc) => doc.exists);
  }

  /// Verifica si la novela está en favoritos (Future).
  static Future<bool> isFavorite(String userId, String novelId) async {
    final doc = await _favRef(userId).doc(novelId).get();
    return doc.exists;
  }

  /// Alterna favorito + suscripción/baja de FCM.
  static Future<void> toggleFavorite(
    String userId,
    Novel novel,
  ) async {
    final ref = _favRef(userId).doc(novel.id);
    final doc = await ref.get();
    final topic = _topicName(novel.id);

    if (doc.exists) {
      await ref.delete();
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        debugPrint('[NovelFav] Desuscrito de FCM: $topic');
      } catch (e) {
        debugPrint('[NovelFav] Error al desuscribirse de $topic: $e');
      }
    } else {
      final fav = FavoriteNovel(
        novelId: novel.id,
        title: novel.title,
        coverUrl: novel.coverUrl,
        status: novel.status,
        author: novel.author,
        addedAt: DateTime.now(),
      );
      await ref.set(fav.toFirestore());
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('[NovelFav] Suscrito a FCM: $topic');
      } catch (e) {
        debugPrint('[NovelFav] Error al suscribirse a $topic: $e');
      }
      await TrackedSeriesService.registerNovel(
        topic: topic,
        novelId: novel.id,
        title: novel.title,
        image: novel.coverUrl,
      );
    }
  }

  /// Sincroniza las suscripciones FCM de todos los favoritos del usuario.
  static Future<void> syncFavoriteTopics(String userId) async {
    try {
      final snap = await _favRef(userId).get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final novelId = data?['novelId'] as String?;
        if (novelId != null && novelId.isNotEmpty) {
          final topic = _topicName(novelId);
          try {
            await FirebaseMessaging.instance.subscribeToTopic(topic);
          } catch (e) {
            debugPrint('[NovelFav] Error al sincronizar $topic: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[NovelFav] Error en syncFavoriteTopics: $e');
    }
  }
}
