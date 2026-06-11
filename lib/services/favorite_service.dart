import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/anime.dart';
import 'follow_service.dart';
import 'tracked_series_service.dart';

/// Modelo ligero para representar un favorito guardado en Firestore.
class FavoriteAnime {
  final String animeUrl;
  final String title;
  final String? image;
  final String? type;
  final String? status;
  final double? score;
  final List<String> genres;
  final DateTime addedAt;

  FavoriteAnime({
    required this.animeUrl,
    required this.title,
    this.image,
    this.type,
    this.status,
    this.score,
    this.genres = const [],
    required this.addedAt,
  });

  factory FavoriteAnime.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoriteAnime(
      animeUrl: data['animeUrl'] ?? '',
      title: data['title'] ?? 'Sin Título',
      image: data['image'],
      type: data['type'],
      status: data['status'],
      score: (data['score'] as num?)?.toDouble(),
      genres: List<String>.from(data['genres'] ?? []),
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'animeUrl': animeUrl,
      'title': title,
      'image': image,
      'type': type,
      'status': status,
      'score': score,
      'genres': genres,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }
}

class FavoriteService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _favRef(String userId) {
    return _db.collection('users').doc(userId).collection('favorites');
  }

  /// Stream en tiempo real de favoritos del usuario.
  static Stream<List<FavoriteAnime>> getFavorites(String userId) {
    return _favRef(userId)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FavoriteAnime.fromFirestore(doc)).toList());
  }

  /// Verifica si un anime está en favoritos. Usa el URL como ID de documento.
  static Future<bool> isFavorite(String userId, String animeUrl) async {
    final docId = _urlToDocId(animeUrl);
    final doc = await _favRef(userId).doc(docId).get();
    return doc.exists;
  }

  /// Stream que emite true/false en tiempo real si el anime está en favoritos.
  static Stream<bool> isFavoriteStream(String userId, String animeUrl) {
    final docId = _urlToDocId(animeUrl);
    return _favRef(userId).doc(docId).snapshots().map((doc) => doc.exists);
  }

  /// Helper to generate a clean topic name for FCM.
  static String _getTopicName(String animeUrl) {
    try {
      final slug = Uri.parse(animeUrl).pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => animeUrl.hashCode.toString(),
          );
      // Sanitize slug for FCM topic: only allow [a-zA-Z0-9-_.~%]
      final cleanSlug = slug.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
      final topic = 'anime_$cleanSlug';
      return topic.length > 900 ? topic.substring(0, 900) : topic;
    } catch (_) {
      return 'anime_${animeUrl.hashCode}';
    }
  }

  /// Alterna favorito: si existe lo borra, si no existe lo agrega.
  static Future<void> toggleFavorite(
    String userId,
    AnimeDetails details,
    String animeUrl, {
    String? fallbackImage,
  }) async {
    final docId = _urlToDocId(animeUrl);
    final ref = _favRef(userId).doc(docId);
    final doc = await ref.get();
    final topic = _getTopicName(animeUrl);

    if (doc.exists) {
      await ref.delete();
      // Solo desuscribirse del tema si tampoco se está siguiendo
      final isFollowing = await FollowService.isFollowing(userId, animeUrl);
      if (!isFollowing) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
          debugPrint('Unsubscribed from FCM topic (via unfavorite): $topic');
        } catch (e) {
          debugPrint('Error unsubscribing from topic $topic: $e');
        }
      }
    } else {
      final fav = FavoriteAnime(
        animeUrl: animeUrl,
        title: details.title,
        image: details.image ?? fallbackImage,
        type: details.type,
        status: details.status,
        score: details.score,
        genres: details.genres.map((g) => g.name).toList(),
        addedAt: DateTime.now(),
      );
      await ref.set(fav.toFirestore());
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('Subscribed to FCM topic: $topic');
      } catch (e) {
        debugPrint('Error subscribing to topic $topic: $e');
      }
      await TrackedSeriesService.registerAnime(
        topic: topic,
        animeUrl: animeUrl,
        title: details.title,
        image: details.image ?? fallbackImage,
      );
    }
  }

  /// Sincroniza todos los favoritos del usuario para suscribirse a sus respectivos canales de FCM.
  static Future<void> syncFavoriteTopics(String userId) async {
    try {
      final snap = await _favRef(userId).get();
      final List<Future<void>> futures = [];
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final animeUrl = data?['animeUrl'] as String?;
        if (animeUrl != null && animeUrl.isNotEmpty) {
          final topic = _getTopicName(animeUrl);
          futures.add(FirebaseMessaging.instance.subscribeToTopic(topic).then((_) {
            debugPrint('Synced subscription to FCM topic: $topic');
          }).catchError((e) {
            debugPrint('Error syncing subscription to topic $topic: $e');
          }));
        }
      }
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
    } catch (e) {
      debugPrint('Error in syncFavoriteTopics: $e');
    }
  }

  /// Convierte una URL a un ID de documento Firestore válido (sin slashes ni caracteres especiales).
  static String _urlToDocId(String url) {
    return Uri.encodeComponent(url).replaceAll('%', '_').substring(0, 
        Uri.encodeComponent(url).replaceAll('%', '_').length > 200 ? 200 : Uri.encodeComponent(url).replaceAll('%', '_').length);
  }
}
