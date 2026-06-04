import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String userId;
  final String userDisplayName;
  final String? userPhotoUrl;
  final String text;
  final String? imageUrl;
  final String? stickerUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final double? episodeNumber;
  final String? parentId;
  final String? replyToUserId;
  final String? replyToUserName;

  Comment({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    this.userPhotoUrl,
    required this.text,
    this.imageUrl,
    this.stickerUrl,
    required this.createdAt,
    this.updatedAt,
    this.episodeNumber,
    this.parentId,
    this.replyToUserId,
    this.replyToUserName,
  });

  bool get isReply => parentId != null && parentId!.isNotEmpty;
  bool get wasEdited => updatedAt != null && updatedAt!.isAfter(createdAt.add(const Duration(seconds: 2)));

  bool get hasSticker => stickerUrl != null && stickerUrl!.isNotEmpty;

  Comment withAuthor({String? displayName, String? photoUrl, String? replyToName}) {
    return Comment(
      id: id,
      userId: userId,
      userDisplayName: displayName ?? userDisplayName,
      userPhotoUrl: photoUrl ?? userPhotoUrl,
      text: text,
      imageUrl: imageUrl,
      stickerUrl: stickerUrl ?? this.stickerUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      episodeNumber: episodeNumber,
      parentId: parentId,
      replyToUserId: replyToUserId,
      replyToUserName: replyToName ?? replyToUserName,
    );
  }

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final created = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Comment(
      id: doc.id,
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? 'Usuario',
      userPhotoUrl: data['userPhotoUrl'],
      text: data['text'] ?? '',
      imageUrl: data['imageUrl']?.toString(),
      stickerUrl: data['stickerUrl']?.toString(),
      createdAt: created,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      episodeNumber: (data['episodeNumber'] as num?)?.toDouble(),
      parentId: data['parentId']?.toString(),
      replyToUserId: data['replyToUserId']?.toString(),
      replyToUserName: data['replyToUserName']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userPhotoUrl': userPhotoUrl,
      'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (stickerUrl != null) 'stickerUrl': stickerUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      'episodeNumber': episodeNumber,
      if (parentId != null) 'parentId': parentId,
      if (replyToUserId != null) 'replyToUserId': replyToUserId,
      if (replyToUserName != null) 'replyToUserName': replyToUserName,
    };
  }
}

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String animeSlug;
  final String animeTitle;
  final String? animeUrl;
  final String? episodeUrl;
  final String? commentId;
  final String? parentCommentId;
  final double? episodeNumber;
  final String fromUserId;
  final String fromUserName;
  final bool read;
  final DateTime createdAt;
  final String? mediaType;
  final String? mangaId;
  final String? novelId;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.animeSlug,
    required this.animeTitle,
    this.animeUrl,
    this.episodeUrl,
    this.commentId,
    this.parentCommentId,
    this.episodeNumber,
    required this.fromUserId,
    required this.fromUserName,
    required this.read,
    required this.createdAt,
    this.mediaType,
    this.mangaId,
    this.novelId,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      type: data['type'] ?? 'comment_reply',
      title: data['title'] ?? 'Nueva respuesta',
      body: data['body'] ?? '',
      animeSlug: data['animeSlug'] ?? data['anime_slug'] ?? '',
      animeTitle: data['animeTitle'] ?? data['anime_title'] ?? 'Anime',
      animeUrl: data['animeUrl']?.toString() ?? data['anime_url']?.toString(),
      episodeUrl: data['episodeUrl']?.toString() ?? data['episode_url']?.toString(),
      commentId: data['commentId']?.toString() ?? data['comment_id']?.toString(),
      parentCommentId: data['parentCommentId']?.toString() ?? data['parent_comment_id']?.toString(),
      episodeNumber: (data['episodeNumber'] as num?)?.toDouble() ??
                     (data['episode_number'] as num?)?.toDouble() ??
                     double.tryParse(data['episodeNumber']?.toString() ?? data['episode_number']?.toString() ?? ''),
      fromUserId: data['fromUserId'] ?? data['from_user_id'] ?? '',
      fromUserName: data['fromUserName'] ?? data['from_user_name'] ?? 'Usuario',
      read: data['read'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      mediaType: data['mediaType']?.toString() ?? data['media_type']?.toString(),
      mangaId: data['mangaId']?.toString() ?? data['manga_id']?.toString(),
      novelId: data['novelId']?.toString() ?? data['novel_id']?.toString(),
    );
  }
}
