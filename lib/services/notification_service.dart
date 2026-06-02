import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment.dart';

class NotificationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _notificationsRef(String userId) {
    return _db.collection('users').doc(userId).collection('notifications');
  }

  static Stream<List<AppNotification>> watchNotifications(String userId) {
    return _notificationsRef(userId)
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppNotification.fromFirestore(d)).toList());
  }

  static Stream<int> watchUnreadCount(String userId) {
    return _notificationsRef(userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) {
          return snap.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return data != null && data['read'] != true;
          }).length;
        });
  }

  static Future<int> countUnread(String userId) async {
    final snap = await _notificationsRef(userId).orderBy('createdAt', descending: true).limit(100).get();
    return snap.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      return data != null && data['read'] != true;
    }).length;
  }

  static Future<void> notifyCommentReply({
    required String targetUserId,
    required String fromUserId,
    required String fromUserName,
    required String animeSlug,
    required String animeTitle,
    String? animeUrl,
    String? episodeUrl,
    double? episodeNumber,
    required String commentId,
    String? parentCommentId,
    required String preview,
  }) async {
    if (targetUserId.isEmpty || targetUserId == fromUserId) return;

    final snippet = preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;

    final title = '$fromUserName respondió tu comentario';
    await _notificationsRef(targetUserId).add({
      'type': 'comment_reply',
      'title': title,
      'body': snippet,
      'animeSlug': animeSlug,
      'animeTitle': animeTitle,
      'animeUrl': animeUrl,
      if (episodeUrl != null && episodeUrl.isNotEmpty) 'episodeUrl': episodeUrl,
      'episodeNumber': episodeNumber,
      'commentId': commentId,
      'parentCommentId': parentCommentId,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> markAsRead(String userId, String notificationId) async {
    await _notificationsRef(userId).doc(notificationId).update({'read': true});
  }

  static Future<void> markAllRead(String userId) async {
    final snap = await _notificationsRef(userId).where('read', isEqualTo: false).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}
