import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment.dart';
import 'notification_service.dart';

class CommentService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _commentsRef(String animeSlug) {
    return _db.collection('comments').doc(animeSlug).collection('entries');
  }

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

  static Future<String> addComment({
    required String animeSlug,
    required String animeTitle,
    String? animeUrl,
    String? episodeUrl,
    required String userId,
    required String userDisplayName,
    String? userPhotoUrl,
    required String text,
    String? imageUrl,
    String? stickerUrl,
    double? episodeNumber,
    String? parentId,
    String? replyToUserId,
    String? replyToUserName,
  }) async {
    final comment = Comment(
      id: '',
      userId: userId,
      userDisplayName: userDisplayName,
      userPhotoUrl: userPhotoUrl,
      text: text.trim(),
      imageUrl: imageUrl,
      stickerUrl: stickerUrl,
      createdAt: DateTime.now(),
      episodeNumber: episodeNumber,
      parentId: parentId,
      replyToUserId: replyToUserId,
      replyToUserName: replyToUserName,
    );

    final doc = await _commentsRef(animeSlug).add(comment.toFirestore());

    if (replyToUserId != null &&
        replyToUserId.isNotEmpty &&
        replyToUserId != userId) {
      await NotificationService.notifyCommentReply(
        targetUserId: replyToUserId,
        fromUserId: userId,
        fromUserName: userDisplayName,
        animeSlug: animeSlug,
        animeTitle: animeTitle,
        animeUrl: animeUrl,
        episodeUrl: episodeUrl,
        episodeNumber: episodeNumber,
        commentId: doc.id,
        parentCommentId: parentId,
        preview: hasStickerPreview(text, stickerUrl),
      );
    }

    return doc.id;
  }

  static Future<void> updateComment({
    required String animeSlug,
    required String commentId,
    required String userId,
    required String text,
    String? imageUrl,
    bool removeImage = false,
  }) async {
    final ref = _commentsRef(animeSlug).doc(commentId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;
    if (data['userId'] != userId) return;

    final updates = <String, dynamic>{
      'text': text.trim(),
      'updatedAt': Timestamp.now(),
    };

    if (removeImage) {
      updates['imageUrl'] = FieldValue.delete();
    } else if (imageUrl != null) {
      updates['imageUrl'] = imageUrl;
    }

    await ref.update(updates);
  }

  static String hasStickerPreview(String text, String? stickerUrl) {
    if (stickerUrl != null && stickerUrl.isNotEmpty) {
      return text.trim().isEmpty ? '🎭 Sticker' : '${text.trim()} 🎭';
    }
    return text.trim();
  }

  static Future<void> deleteComment(String animeSlug, String commentId) async {
    await _commentsRef(animeSlug).doc(commentId).delete();
  }

  /// Propaga nombre y foto actuales a todos los comentarios del usuario.
  static Future<int> syncAuthorProfile({
    required String uid,
    required String displayName,
    String? photoUrl,
  }) async {
    var updated = 0;
    final batchLimit = 400;

    Future<void> applyUpdates(QuerySnapshot snap, Map<String, dynamic> fields) async {
      if (snap.docs.isEmpty) return;
      for (var i = 0; i < snap.docs.length; i += batchLimit) {
        final chunk = snap.docs.skip(i).take(batchLimit);
        final batch = _db.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, fields);
        }
        await batch.commit();
        updated += chunk.length;
      }
    }

    final ownComments = await _db
        .collectionGroup('entries')
        .where('userId', isEqualTo: uid)
        .get();

    final authorFields = <String, dynamic>{
      'userDisplayName': displayName,
      if (photoUrl != null) 'userPhotoUrl': photoUrl,
    };
    await applyUpdates(ownComments, authorFields);

    final repliesMention = await _db
        .collectionGroup('entries')
        .where('replyToUserId', isEqualTo: uid)
        .get();

    await applyUpdates(repliesMention, {'replyToUserName': displayName});

    return updated;
  }
}
