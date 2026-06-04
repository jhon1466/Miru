import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/novel_history_item.dart';

class NovelHistoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ref(String userId) {
    return _db.collection('users').doc(userId).collection('novel_history');
  }

  /// Stream en tiempo real del historial de novelas.
  static Stream<List<NovelHistoryItem>> historyStream(String userId) {
    return _ref(userId)
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => NovelHistoryItem.fromFirestore(doc)).toList(),
        );
  }

  /// Registra o actualiza una entrada de historial.
  static Future<void> upsertEntry(String userId, NovelHistoryItem item) async {
    await _ref(userId).doc(item.novelId).set(item.toFirestore(), SetOptions(merge: true));
  }

  /// Elimina una entrada de historial.
  static Future<void> removeEntry(String userId, String novelId) async {
    await _ref(userId).doc(novelId).delete();
  }

  /// Vacía todo el historial de novelas del usuario.
  static Future<void> clearAll(String userId) async {
    final snap = await _ref(userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Fusiona el historial local con la nube (usado al iniciar sesión).
  static Future<void> mergeLocalToCloud(String userId, List<NovelHistoryItem> localItems) async {
    for (final item in localItems) {
      await upsertEntry(userId, item);
    }
  }
}
