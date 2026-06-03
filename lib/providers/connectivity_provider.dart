import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

class ConnectivityProvider extends ChangeNotifier {
  bool _isConnected = true;
  Timer? _timer;

  bool get isConnected => _isConnected;

  ConnectivityProvider() {
    _startMonitoring();
  }

  void _startMonitoring() {
    // Verificar conexión al inicio
    checkConnection();
    // Volver a verificar periódicamente cada 5 segundos
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => checkConnection());
  }

  Future<void> checkConnection() async {
    try {
      // dns.google es una dirección sumamente confiable y rápida
      final result = await InternetAddress.lookup('dns.google').timeout(const Duration(seconds: 3));
      final active = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (_isConnected != active) {
        _isConnected = active;
        notifyListeners();
      }
    } catch (_) {
      if (_isConnected != false) {
        _isConnected = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
