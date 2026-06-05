import 'package:cloud_firestore/cloud_firestore.dart';

class CompletedMedia {
  final String mediaId;
  final String mediaType;
  final String title;
  final String? image;
  final String? type;
  final String? status;
  final String? author;
  final List<String> genres;
  final DateTime completedAt;

  CompletedMedia({
    required this.mediaId,
    required this.mediaType,
    required this.title,
    this.image,
    this.type,
    this.status,
    this.author,
    this.genres = const [],
    required this.completedAt,
  });

  factory CompletedMedia.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CompletedMedia(
      mediaId: data['mediaId'] ?? '',
      mediaType: data['mediaType'] ?? '',
      title: data['title'] ?? 'Sin Título',
      image: data['image'],
      type: data['type'],
      status: data['status'],
      author: data['author'],
      genres: List<String>.from(data['genres'] ?? []),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'mediaId': mediaId,
      'mediaType': mediaType,
      'title': title,
      'image': image,
      'type': type,
      'status': status,
      'author': author,
      'genres': genres,
      'completedAt': Timestamp.fromDate(completedAt),
    };
  }
}

class CompletedService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference _completedRef(String userId) {
    return _db.collection('users').doc(userId).collection('completed');
  }

  static String _urlToDocId(String url) {
    return Uri.encodeComponent(url).replaceAll('%', '_').substring(0, 
        Uri.encodeComponent(url).replaceAll('%', '_').length > 200 ? 200 : Uri.encodeComponent(url).replaceAll('%', '_').length);
  }

  /// Stream que emite si un contenido está completado o no.
  static Stream<bool> isCompletedStream(String userId, String mediaId) {
    final docId = _urlToDocId(mediaId);
    return _completedRef(userId).doc(docId).snapshots().map((doc) => doc.exists);
  }

  /// Stream de contenidos completados filtrados por tipo.
  static Stream<List<CompletedMedia>> getCompleted(String userId, String mediaType) {
    return _completedRef(userId)
        .where('mediaType', isEqualTo: mediaType)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => CompletedMedia.fromFirestore(doc)).toList());
  }

  /// Alterna el estado de completado.
  static Future<void> toggleCompleted({
    required String userId,
    required String mediaId,
    required String mediaType,
    required String title,
    String? image,
    String? type,
    String? status,
    String? author,
    List<String> genres = const [],
  }) async {
    final docId = _urlToDocId(mediaId);
    final ref = _completedRef(userId).doc(docId);
    final doc = await ref.get();

    if (doc.exists) {
      await ref.delete();
    } else {
      final item = CompletedMedia(
        mediaId: mediaId,
        mediaType: mediaType,
        title: title,
        image: image,
        type: type,
        status: status,
        author: author,
        genres: genres,
        completedAt: DateTime.now(),
      );
      await ref.set(item.toFirestore());
    }
  }
}
