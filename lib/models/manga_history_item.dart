import 'package:cloud_firestore/cloud_firestore.dart';

class MangaHistoryItem {
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterNumber;
  final int page;
  final DateTime timestamp;

  MangaHistoryItem({
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterNumber,
    required this.page,
    required this.timestamp,
  });

  factory MangaHistoryItem.fromJson(Map<String, dynamic> json) {
    return MangaHistoryItem(
      mangaId: json['mangaId'] ?? '',
      mangaTitle: json['mangaTitle'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
      chapterId: json['chapterId'] ?? '',
      chapterNumber: json['chapterNumber']?.toString() ?? '',
      page: json['page'] as int? ?? 1,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  factory MangaHistoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MangaHistoryItem(
      mangaId: data['mangaId']?.toString() ?? '',
      mangaTitle: data['mangaTitle']?.toString() ?? '',
      coverUrl: data['coverUrl']?.toString() ?? '',
      chapterId: data['chapterId']?.toString() ?? '',
      chapterNumber: data['chapterNumber']?.toString() ?? '',
      page: data['page'] as int? ?? 1,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mangaId': mangaId,
      'mangaTitle': mangaTitle,
      'coverUrl': coverUrl,
      'chapterId': chapterId,
      'chapterNumber': chapterNumber,
      'page': page,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'mangaId': mangaId,
      'mangaTitle': mangaTitle,
      'coverUrl': coverUrl,
      'chapterId': chapterId,
      'chapterNumber': chapterNumber,
      'page': page,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
