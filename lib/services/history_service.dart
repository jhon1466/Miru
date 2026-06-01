import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/history_provider.dart';

class HistoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ref(String userId) {
    return _db.collection('users').doc(userId).collection('watch_history');
  }

  static String _docId(String episodeUrl) {
    return episodeUrl.hashCode.toRadixString(16);
  }

  static Stream<List<HistoryItem>> watchHistoryStream(String userId) {
    return _ref(userId)
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => HistoryItem.fromFirestore(doc)).toList(),
        );
  }

  static Future<void> upsertEntry(String userId, HistoryItem item) async {
    await _ref(userId).doc(_docId(item.episodeUrl)).set(item.toFirestore(), SetOptions(merge: true));
  }

  static Future<void> removeEntry(String userId, String episodeUrl) async {
    await _ref(userId).doc(_docId(episodeUrl)).delete();
  }

  static Future<void> clearAll(String userId) async {
    final snap = await _ref(userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static Future<void> mergeLocalToCloud(String userId, List<HistoryItem> localItems) async {
    for (final item in localItems) {
      await upsertEntry(userId, item);
    }
  }
}
