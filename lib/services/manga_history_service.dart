import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/manga_history_item.dart';

class MangaHistoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ref(String userId) {
    return _db.collection('users').doc(userId).collection('manga_history');
  }

  /// Stream en tiempo real del historial de mangas.
  static Stream<List<MangaHistoryItem>> historyStream(String userId) {
    return _ref(userId)
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => MangaHistoryItem.fromFirestore(doc)).toList(),
        );
  }

  /// Registra o actualiza una entrada de historial.
  static Future<void> upsertEntry(String userId, MangaHistoryItem item) async {
    await _ref(userId).doc(item.mangaId).set(item.toFirestore(), SetOptions(merge: true));
  }

  /// Elimina una entrada de historial.
  static Future<void> removeEntry(String userId, String mangaId) async {
    await _ref(userId).doc(mangaId).delete();
  }

  /// Vacía todo el historial de mangas del usuario.
  static Future<void> clearAll(String userId) async {
    final snap = await _ref(userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Fusiona el historial local con la nube.
  static Future<void> mergeLocalToCloud(String userId, List<MangaHistoryItem> localItems) async {
    for (final item in localItems) {
      await upsertEntry(userId, item);
    }
  }
}
