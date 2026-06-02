import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/anime.dart';
import 'favorite_service.dart';

class FollowService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _followRef(String userId) {
    return _db.collection('users').doc(userId).collection('following');
  }

  /// Verifica si un anime se está siguiendo (Stream).
  static Stream<bool> isFollowingStream(String userId, String animeUrl) {
    final docId = _urlToDocId(animeUrl);
    return _followRef(userId).doc(docId).snapshots().map((doc) => doc.exists);
  }

  /// Verifica si un anime se está siguiendo (Future).
  static Future<bool> isFollowing(String userId, String animeUrl) async {
    final docId = _urlToDocId(animeUrl);
    final doc = await _followRef(userId).doc(docId).get();
    return doc.exists;
  }

  static String _getTopicName(String animeUrl) {
    try {
      final slug = Uri.parse(animeUrl).pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => animeUrl.hashCode.toString(),
          );
      final cleanSlug = slug.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
      final topic = 'anime_$cleanSlug';
      return topic.length > 900 ? topic.substring(0, 900) : topic;
    } catch (_) {
      return 'anime_${animeUrl.hashCode}';
    }
  }

  /// Alterna seguir anime.
  static Future<void> toggleFollow(
    String userId,
    AnimeDetails details,
    String animeUrl, {
    String? fallbackImage,
  }) async {
    final docId = _urlToDocId(animeUrl);
    final ref = _followRef(userId).doc(docId);
    final doc = await ref.get();
    final topic = _getTopicName(animeUrl);

    if (doc.exists) {
      await ref.delete();
      // Solo desuscribirse del tema si tampoco está en favoritos
      final isFav = await FavoriteService.isFavorite(userId, animeUrl);
      if (!isFav) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
          debugPrint('Unsubscribed from FCM topic (via unfollow): $topic');
        } catch (e) {
          debugPrint('Error unsubscribing from topic $topic: $e');
        }
      }
    } else {
      await ref.set({
        'animeUrl': animeUrl,
        'title': details.title,
        'image': details.image ?? fallbackImage,
        'status': details.status,
        'followedAt': FieldValue.serverTimestamp(),
      });
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('Subscribed to FCM topic (via follow): $topic');
      } catch (e) {
        debugPrint('Error subscribing to topic $topic: $e');
      }
    }
  }

  static String _urlToDocId(String url) {
    return Uri.encodeComponent(url).replaceAll('%', '_').substring(0, 
        Uri.encodeComponent(url).replaceAll('%', '_').length > 200 ? 200 : Uri.encodeComponent(url).replaceAll('%', '_').length);
  }
}
