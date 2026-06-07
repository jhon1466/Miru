import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/supporter_service.dart';

class SupporterProvider extends ChangeNotifier {
  bool _isSupporter = false;
  StreamSubscription<bool>? _sub;

  bool get isSupporter => _isSupporter;

  /// Límite de caracteres por mensaje
  int get maxMessageLength => _isSupporter ? 2000 : 500;

  /// Cooldown entre mensajes (0 = sin cooldown)
  Duration get messageCooldown =>
      _isSupporter ? Duration.zero : const Duration(seconds: 3);

  void bindUser(String? uid) {
    _sub?.cancel();
    if (uid == null) {
      _isSupporter = false;
      notifyListeners();
      return;
    }
    _sub = SupporterService.supporterStream(uid).listen((value) {
      if (_isSupporter != value) {
        _isSupporter = value;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
