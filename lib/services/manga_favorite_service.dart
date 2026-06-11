import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/manga.dart';
import 'manga_follow_service.dart';
import 'tracked_series_service.dart';

class FavoriteManga {
  final String mangaId;
  final String title;
  final String? coverUrl;
  final String? status;
  final int? year;
  final DateTime addedAt;

  FavoriteManga({
    required this.mangaId,
    required this.title,
    this.coverUrl,
    this.status,
    this.year,
    required this.addedAt,
  });

  factory FavoriteManga.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoriteManga(
      mangaId: data['mangaId'] ?? '',
      title: data['title'] ?? 'Sin Título',
      coverUrl: data['coverUrl'],
      status: data['status'],
      year: data['year'] != null ? int.tryParse(data['year'].toString()) : null,
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'mangaId': mangaId,
      'title': title,
      'coverUrl': coverUrl,
      'status': status,
      'year': year,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }
}

class MangaFavoriteService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _favRef(String userId) {
    return _db.collection('users').doc(userId).collection('manga_favorites');
  }

  /// Stream en tiempo real de favoritos del usuario.
  static Stream<List<FavoriteManga>> getFavorites(String userId) {
    return _favRef(userId)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FavoriteManga.fromFirestore(doc)).toList());
  }

  /// Verifica si un manga está en favoritos (Future).
  static Future<bool> isFavorite(String userId, String mangaId) async {
    final doc = await _favRef(userId).doc(mangaId).get();
    return doc.exists;
  }

  /// Stream que emite si el manga está en favoritos.
  static Stream<bool> isFavoriteStream(String userId, String mangaId) {
    return _favRef(userId).doc(mangaId).snapshots().map((doc) => doc.exists);
  }

  /// Alterna favorito.
  static Future<void> toggleFavorite(
    String userId,
    Manga details, {
    String? fallbackImage,
  }) async {
    final ref = _favRef(userId).doc(details.id);
    final doc = await ref.get();
    final topic = 'manga_${details.id}';

    if (doc.exists) {
      await ref.delete();
      final isFollowing = await MangaFollowService.isFollowing(userId, details.id);
      if (!isFollowing) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        } catch (e) {
          debugPrint('[MangaFav] error al desuscribirse de $topic: $e');
        }
      }
    } else {
      final fav = FavoriteManga(
        mangaId: details.id,
        title: details.title,
        coverUrl: details.coverUrl ?? fallbackImage,
        status: details.status,
        year: details.year,
        addedAt: DateTime.now(),
      );
      await ref.set(fav.toFirestore());
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('[MangaFav] suscrito a FCM: $topic');
      } catch (e) {
        debugPrint('[MangaFav] error al suscribirse a $topic: $e');
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
