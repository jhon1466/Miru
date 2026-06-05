import 'package:cloud_firestore/cloud_firestore.dart';

class RatingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Convierte una URL o ID a un ID de documento Firestore válido.
  static String _urlToDocId(String url) {
    return Uri.encodeComponent(url).replaceAll('%', '_').substring(0, 
        Uri.encodeComponent(url).replaceAll('%', '_').length > 200 ? 200 : Uri.encodeComponent(url).replaceAll('%', '_').length);
  }

  /// Stream que emite el rating actual del usuario (o null si no ha votado).
  static Stream<double?> getUserRatingStream({
    required String userId,
    required String mediaId,
    required String mediaType,
  }) {
    final cleanDocId = _urlToDocId(mediaId);
    return _db
        .collection('users')
        .doc(userId)
        .collection('ratings')
        .doc(cleanDocId)
        .snapshots()
        .map((doc) => doc.exists ? (doc.data()?['rating'] as num?)?.toDouble() : null);
  }

  /// Stream que emite las estadísticas globales de valoración (promedio y cantidad de votos).
  static Stream<Map<String, dynamic>> getMediaRatingStatsStream({
    required String mediaId,
    required String mediaType,
  }) {
    final cleanDocId = _urlToDocId(mediaId);
    return _db
        .collection('media_ratings')
        .doc(cleanDocId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) {
            return {
              'average': 0.0,
              'count': 0,
            };
          }
          final data = doc.data() ?? {};
          return {
            'average': (data['average'] as num?)?.toDouble() ?? 0.0,
            'count': (data['count'] as num?)?.toInt() ?? 0,
          };
        });
  }

  /// Registra o actualiza la valoración de un usuario para un anime/manga/novela.
  static Future<void> rateMedia({
    required String userId,
    required String mediaId,
    required String mediaType,
    required String title,
    String? image,
    required double rating,
  }) async {
    final cleanDocId = _urlToDocId(mediaId);
    
    final userRatingRef = _db.collection('users').doc(userId).collection('ratings').doc(cleanDocId);
    final mediaRatingRef = _db.collection('media_ratings').doc(cleanDocId);
    final mediaUserRatingRef = mediaRatingRef.collection('user_ratings').doc(userId);

    await _db.runTransaction((transaction) async {
      final userRatingSnap = await transaction.get(userRatingRef);
      final double? oldRating = userRatingSnap.exists ? (userRatingSnap.data()?['rating'] as num?)?.toDouble() : null;

      final mediaStatsSnap = await transaction.get(mediaRatingRef);
      double currentSum = 0.0;
      int currentCount = 0;

      if (mediaStatsSnap.exists) {
        final data = mediaStatsSnap.data()!;
        currentSum = (data['sum'] as num?)?.toDouble() ?? 0.0;
        currentCount = (data['count'] as num?)?.toInt() ?? 0;
      }

      if (oldRating != null) {
        currentSum = currentSum - oldRating + rating;
      } else {
        currentSum = currentSum + rating;
        currentCount = currentCount + 1;
      }

      double average = currentCount > 0 ? currentSum / currentCount : 0.0;

      transaction.set(userRatingRef, {
        'mediaId': mediaId,
        'mediaType': mediaType,
        'title': title,
        'image': image,
        'rating': rating,
        'ratedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(mediaUserRatingRef, {
        'rating': rating,
        'ratedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(mediaRatingRef, {
        'mediaId': mediaId,
        'mediaType': mediaType,
        'title': title,
        'image': image,
        'sum': currentSum,
        'count': currentCount,
        'average': average,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Elimina la valoración de un usuario.
  static Future<void> deleteRating({
    required String userId,
    required String mediaId,
    required String mediaType,
  }) async {
    final cleanDocId = _urlToDocId(mediaId);
    
    final userRatingRef = _db.collection('users').doc(userId).collection('ratings').doc(cleanDocId);
    final mediaRatingRef = _db.collection('media_ratings').doc(cleanDocId);
    final mediaUserRatingRef = mediaRatingRef.collection('user_ratings').doc(userId);

    await _db.runTransaction((transaction) async {
      final userRatingSnap = await transaction.get(userRatingRef);
      if (!userRatingSnap.exists) return;

      final double oldRating = (userRatingSnap.data()?['rating'] as num?)?.toDouble() ?? 0.0;

      final mediaStatsSnap = await transaction.get(mediaRatingRef);
      double currentSum = 0.0;
      int currentCount = 0;

      if (mediaStatsSnap.exists) {
        final data = mediaStatsSnap.data()!;
        currentSum = (data['sum'] as num?)?.toDouble() ?? 0.0;
        currentCount = (data['count'] as num?)?.toInt() ?? 0;
      }

      currentSum = (currentSum - oldRating).clamp(0.0, double.infinity);
      currentCount = (currentCount - 1).clamp(0, 99999999);
      double average = currentCount > 0 ? currentSum / currentCount : 0.0;

      transaction.delete(userRatingRef);
      transaction.delete(mediaUserRatingRef);

      if (currentCount > 0) {
        transaction.set(mediaRatingRef, {
          'sum': currentSum,
          'count': currentCount,
          'average': average,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        transaction.delete(mediaRatingRef);
      }
    });
  }
}
