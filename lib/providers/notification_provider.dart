import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';

/// Contador y estado de notificaciones en toda la app (sin reiniciar).
class NotificationProvider extends ChangeNotifier {
  StreamSubscription<int>? _unreadSub;
  String? _userId;
  int _unreadCount = 0;

  int get unreadCount => _unreadCount;

  void bindUser(String? userId) {
    if (_userId == userId) return;
    _unreadSub?.cancel();
    _unreadSub = null;
    _userId = userId;
    _unreadCount = 0;

    if (userId == null || userId.isEmpty) {
      notifyListeners();
      return;
    }

    _unreadSub = NotificationService.watchUnreadCount(userId).listen(
      (count) {
        _unreadCount = count;
        notifyListeners();
      },
      onError: (e) => debugPrint('NotificationProvider stream: $e'),
    );
  }

  /// Llamar al recibir push en primer plano (Firestore puede tardar un instante).
  void refreshUnread() {
    if (_userId == null) return;
    NotificationService.countUnread(_userId!).then((count) {
      if (_unreadCount != count) {
        _unreadCount = count;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }
}
