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
    Query query = _commentsRef(animeSlug).orderBy('createdAt', descending: false);

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
    required String userId,
    required String userDisplayName,
    String? userPhotoUrl,
    required String text,
    String? imageUrl,
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
        episodeNumber: episodeNumber,
        commentId: doc.id,
        parentCommentId: parentId,
        preview: text.trim(),
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

  static Future<void> deleteComment(String animeSlug, String commentId) async {
    await _commentsRef(animeSlug).doc(commentId).delete();
  }
}
