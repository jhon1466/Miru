import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';

/// Contador de notificaciones sin escuchar Firestore en tiempo real (menos lecturas).
class NotificationProvider extends ChangeNotifier {
  Timer? _pollTimer;
  String? _userId;
  int _unreadCount = 0;

  int get unreadCount => _unreadCount;

  void bindUser(String? userId) {
    if (_userId == userId) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    _userId = userId;
    _unreadCount = 0;

    if (userId == null || userId.isEmpty) {
      notifyListeners();
      return;
    }

    refreshUnread();
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) => refreshUnread());
  }

  /// Tras recibir FCM o abrir la bandeja.
  void refreshUnread() {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    NotificationService.countUnread(uid).then((count) {
      if (_unreadCount != count) {
        _unreadCount = count;
        notifyListeners();
      }
    }).catchError((e) {
      debugPrint('NotificationProvider refresh: $e');
    });
  }

  void bumpUnread() {
    _unreadCount += 1;
    notifyListeners();
    refreshUnread();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
