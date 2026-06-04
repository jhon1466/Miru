import 'package:cloud_firestore/cloud_firestore.dart';

class NovelHistoryItem {
  final String novelId;
  final String novelTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterTitle;
  final double chapterNumber;
  final DateTime timestamp;

  NovelHistoryItem({
    required this.novelId,
    required this.novelTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterNumber,
    required this.timestamp,
  });

  factory NovelHistoryItem.fromJson(Map<String, dynamic> json) {
    return NovelHistoryItem(
      novelId: json['novelId'] ?? '',
      novelTitle: json['novelTitle'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
      chapterId: json['chapterId'] ?? '',
      chapterTitle: json['chapterTitle'] ?? '',
      chapterNumber: (json['chapterNumber'] as num?)?.toDouble() ?? 1.0,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  factory NovelHistoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return NovelHistoryItem(
      novelId: data['novelId']?.toString() ?? '',
      novelTitle: data['novelTitle']?.toString() ?? '',
      coverUrl: data['coverUrl']?.toString() ?? '',
      chapterId: data['chapterId']?.toString() ?? '',
      chapterTitle: data['chapterTitle']?.toString() ?? '',
      chapterNumber: (data['chapterNumber'] as num?)?.toDouble() ?? 1.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'novelId': novelId,
      'novelTitle': novelTitle,
      'coverUrl': coverUrl,
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'chapterNumber': chapterNumber,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'novelId': novelId,
      'novelTitle': novelTitle,
      'coverUrl': coverUrl,
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'chapterNumber': chapterNumber,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
