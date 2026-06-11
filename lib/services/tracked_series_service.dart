import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registra las series (anime/manga/novela) que algún usuario sigue o marca
/// como favorito en una colección central `tracked_series`. La función
/// programada del backend (`watchNewChapters`) recorre esa colección, detecta
/// nuevos capítulos y envía la notificación al topic FCM correspondiente.
///
/// El docId es el topic FCM (mismo string al que la app se suscribe), para que
/// el backend pueda enviar directamente a `doc.id`.
class TrackedSeriesService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Helpers de topic (deben coincidir con los de cada *_service) ──────────
  static String animeTopic(String animeUrl) {
    try {
      final slug = Uri.parse(animeUrl).pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => animeUrl.hashCode.toString(),
          );
      final clean = slug.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
      final t = 'anime_$clean';
      return t.length > 900 ? t.substring(0, 900) : t;
    } catch (_) {
      return 'anime_${animeUrl.hashCode}';
    }
  }

  static String mangaTopic(String mangaId) => 'manga_$mangaId';

  static String novelTopic(String novelId) {
    final clean = novelId.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
    final t = 'novel_$clean';
    return t.length > 900 ? t.substring(0, 900) : t;
  }

  // ── Registro ──────────────────────────────────────────────────────────────
  static Future<void> _register(String topic, Map<String, dynamic> data) async {
    if (topic.isEmpty) return;
    try {
      await _db.collection('tracked_series').doc(topic).set({
        'topic': topic,
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TrackedSeries] error registrando $topic: $e');
    }
  }

  static Future<void> registerAnime({
    required String topic,
    required String animeUrl,
    required String title,
    String? image,
  }) =>
      _register(topic, {
        'type': 'anime',
        'animeUrl': animeUrl,
        'title': title,
        'image': image ?? '',
      });

  static Future<void> registerManga({
    required String topic,
    required String mangaId,
    String? slug,
    required String title,
    String? image,
  }) =>
      _register(topic, {
        'type': 'manga',
        'mangaId': mangaId,
        'slug': slug ?? '',
        'title': title,
        'image': image ?? '',
      });

  static Future<void> registerNovel({
    required String topic,
    required String novelId,
    required String title,
    String? image,
  }) =>
      _register(topic, {
        'type': 'novel',
        'novelId': novelId,
        'title': title,
        'image': image ?? '',
      });

  // ── Backfill ────────────────────────────────────────────────────────────────
  /// Registra (y re-suscribe al topic) todas las series que el usuario ya sigue
  /// o tiene en favoritos, para que los seguimientos previos también reciban
  /// avisos de nuevos capítulos. Idempotente; seguro de llamar al iniciar.
  static Future<void> backfillForUser(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    final user = _db.collection('users').doc(userId);
    try {
      // Anime: favorites + following
      for (final col in ['favorites', 'following']) {
        final snap = await user.collection(col).get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final url = (d['animeUrl'] ?? '') as String;
          if (url.isEmpty) continue;
          final topic = animeTopic(url);
          _subscribe(topic);
          await registerAnime(
            topic: topic,
            animeUrl: url,
            title: (d['title'] ?? '') as String,
            image: (d['image'] ?? d['coverUrl'] ?? '') as String?,
          );
        }
      }
      // Manga: manga_favorites + manga_following
      for (final col in ['manga_favorites', 'manga_following']) {
        final snap = await user.collection(col).get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final id = (d['mangaId'] ?? doc.id) as String;
          if (id.isEmpty) continue;
          final topic = mangaTopic(id);
          _subscribe(topic);
          await registerManga(
            topic: topic,
            mangaId: id,
            slug: (d['slug'] ?? '') as String?,
            title: (d['title'] ?? '') as String,
            image: (d['coverUrl'] ?? '') as String?,
          );
        }
      }
      // Novela: novel_favorites + novel_following
      for (final col in ['novel_favorites', 'novel_following']) {
        final snap = await user.collection(col).get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final id = (d['novelId'] ?? doc.id) as String;
          if (id.isEmpty) continue;
          final topic = novelTopic(id);
          _subscribe(topic);
          await registerNovel(
            topic: topic,
            novelId: id,
            title: (d['title'] ?? '') as String,
            image: (d['coverUrl'] ?? '') as String?,
          );
        }
      }
      debugPrint('[TrackedSeries] backfill completado para $userId');
    } catch (e) {
      debugPrint('[TrackedSeries] backfill error: $e');
    }
  }

  static void _subscribe(String topic) {
    FirebaseMessaging.instance.subscribeToTopic(topic).catchError((e) {
      debugPrint('[TrackedSeries] error suscribiendo $topic: $e');
    });
  }
}
