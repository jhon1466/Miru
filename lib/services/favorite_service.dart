import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/anime.dart';

/// Modelo ligero para representar un favorito guardado en Firestore.
class FavoriteAnime {
  final String animeUrl;
  final String title;
  final String? image;
  final String? type;
  final String? status;
  final double? score;
  final DateTime addedAt;

  FavoriteAnime({
    required this.animeUrl,
    required this.title,
    this.image,
    this.type,
    this.status,
    this.score,
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

    if (doc.exists) {
      await ref.delete();
    } else {
      final fav = FavoriteAnime(
        animeUrl: animeUrl,
        title: details.title,
        image: details.image ?? fallbackImage,
        type: details.type,
        status: details.status,
        score: details.score,
        addedAt: DateTime.now(),
      );
      await ref.set(fav.toFirestore());
    }
  }

  /// Convierte una URL a un ID de documento Firestore válido (sin slashes ni caracteres especiales).
  static String _urlToDocId(String url) {
    return Uri.encodeComponent(url).replaceAll('%', '_').substring(0, 
        Uri.encodeComponent(url).replaceAll('%', '_').length > 200 ? 200 : Uri.encodeComponent(url).replaceAll('%', '_').length);
  }
}
