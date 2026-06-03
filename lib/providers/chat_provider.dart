import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rastrea si hay mensajes nuevos en el chat público comparando el timestamp
/// del último mensaje con el último que vio el usuario (guardado en SharedPrefs).
class ChatProvider extends ChangeNotifier {
  static const _prefKey = 'chat_last_seen_ts';

  StreamSubscription<QuerySnapshot>? _sub;
  DateTime? _lastMessageTime;
  DateTime? _lastSeenTime;

  bool get hasUnread {
    if (_lastMessageTime == null) return false;
    if (_lastSeenTime == null) return true;
    return _lastMessageTime!.isAfter(_lastSeenTime!);
  }

  /// Llama a esto cuando el usuario abre el chat.
  Future<void> markSeen() async {
    _lastSeenTime = DateTime.now();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, _lastSeenTime!.millisecondsSinceEpoch);
  }

  /// Inicia el listener del último mensaje.
  Future<void> startListening() async {
    // Cargar el último timestamp visto desde prefs
    final prefs = await SharedPreferences.getInstance();
    final savedMs = prefs.getInt(_prefKey);
    if (savedMs != null) {
      _lastSeenTime = DateTime.fromMillisecondsSinceEpoch(savedMs);
    }

    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('public_chat')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) return;
      final ts = snap.docs.first.data()['timestamp'];
      if (ts is Timestamp) {
        final newTime = ts.toDate();
        if (_lastMessageTime == null || newTime.isAfter(_lastMessageTime!)) {
          _lastMessageTime = newTime;
          notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint('ChatProvider error: $e');
    });
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
