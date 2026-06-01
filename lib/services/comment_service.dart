import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment.dart';

class CommentService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Devuelve la referencia a la subcolección de comentarios de un anime.
  /// Si [episodeNumber] es null, trae comentarios generales del anime.
  /// Si [episodeNumber] tiene valor, trae solo los del episodio.
  static CollectionReference _commentsRef(String animeSlug) {
    return _db.collection('comments').doc(animeSlug).collection('entries');
  }

  /// Stream en tiempo real de comentarios de un anime o episodio.
  static Stream<List<Comment>> getComments(
    String animeSlug, {
    double? episodeNumber,
  }) {
    Query query = _commentsRef(animeSlug).orderBy('createdAt', descending: true);

    if (episodeNumber != null) {
      query = query.where('episodeNumber', isEqualTo: episodeNumber);
    } else {
      query = query.where('episodeNumber', isNull: true);
    }

    return query.snapshots().map(
      (snap) => snap.docs.map((doc) => Comment.fromFirestore(doc)).toList(),
    );
  }

  /// Agrega un nuevo comentario.
  static Future<void> addComment({
    required String animeSlug,
    required String userId,
    required String userDisplayName,
    String? userPhotoUrl,
    required String text,
    double? episodeNumber,
  }) async {
    final comment = Comment(
      id: '',
      userId: userId,
      userDisplayName: userDisplayName,
      userPhotoUrl: userPhotoUrl,
      text: text.trim(),
      createdAt: DateTime.now(),
      episodeNumber: episodeNumber,
    );
    await _commentsRef(animeSlug).add(comment.toFirestore());
  }

  /// Elimina un comentario. Solo debe llamarse si el userId coincide.
  static Future<void> deleteComment(String animeSlug, String commentId) async {
    await _commentsRef(animeSlug).doc(commentId).delete();
  }
}
