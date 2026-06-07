import 'package:cloud_firestore/cloud_firestore.dart';

/// Gestiona el estado de supporter (Patreon) en Firestore.
/// El campo `isSupporter` en /users/{uid} lo activa manualmente el admin
/// o un webhook de Patreon.
class SupporterService {
  static final _db = FirebaseFirestore.instance;

  static Future<bool> isSupporter(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return (doc.data()?['isSupporter'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stream en tiempo real para que el provider reaccione a cambios.
  static Stream<bool> supporterStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => (doc.data()?['isSupporter'] as bool?) ?? false);
  }
}
