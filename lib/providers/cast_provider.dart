import 'dart:async';
import 'package:cast/cast.dart';
import 'package:flutter/foundation.dart';

enum CastState { idle, searching, connecting, connected }

class CastProvider extends ChangeNotifier {
  CastState _state = CastState.idle;
  List<CastDevice> _devices = [];
  CastDevice? _connectedDevice;
  CastSession? _activeSession;
  String? _error;

  CastState get state => _state;
  List<CastDevice> get devices => List.unmodifiable(_devices);
  CastDevice? get connectedDevice => _connectedDevice;
  CastSession? get activeSession => _activeSession;
  String? get error => _error;
  bool get isConnected => _state == CastState.connected && _activeSession != null;
  bool get isSearching => _state == CastState.searching;
  bool get isConnecting => _state == CastState.connecting;

  Future<void> searchDevices() async {
    _state = CastState.searching;
    _devices = [];
    _error = null;
    notifyListeners();

    try {
      final found = await CastDiscoveryService().search(
        timeout: const Duration(seconds: 5),
      );
      _devices = found;
    } catch (e) {
      debugPrint('[Cast] Discovery error: $e');
      _error = 'Error buscando dispositivos';
    }

    if (_state == CastState.searching) {
      _state = CastState.idle;
    }
    notifyListeners();
  }

  Future<bool> connect(CastDevice device) async {
    _state = CastState.connecting;
    _connectedDevice = device;
    _error = null;
    notifyListeners();

    try {
      final session = await CastSession.connect(
        'miru-session',
        device,
        const Duration(seconds: 10),
      );
      _activeSession = session;

      // Listen for state changes
      session.stateStream.listen((state) {
        if (state == CastSessionState.connected) {
          _state = CastState.connected;
          notifyListeners();
          // Launch default media receiver app on the Chromecast
          session.sendMessage(CastSession.kNamespaceReceiver, {
            'type': 'LAUNCH',
            'appId': 'CC1AD845',
          });
        } else if (state == CastSessionState.closed) {
          _onDisconnected();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[Cast] Connect error: $e');
      _error = 'No se pudo conectar al dispositivo';
      _state = CastState.idle;
      _connectedDevice = null;
      _activeSession = null;
      notifyListeners();
      return false;
    }
  }

  /// Envía el video al Chromecast.
  /// [startTime] en segundos — sincroniza desde la posición actual del reproductor local.
  Future<void> loadMedia({
    required String url,
    required String title,
    String? posterUrl,
    double startTime = 0,
  }) async {
    final session = _activeSession;
    if (session == null) return;

    final lower = url.toLowerCase();
    final isHls = lower.contains('.m3u8') ||
        lower.contains('/m3u8/') ||
        lower.contains('/hls/');
    final contentType = isHls ? 'application/x-mpegURL' : 'video/mp4';

    final media = <String, dynamic>{
      'contentId': url,
      'contentType': contentType,
      'streamType': 'BUFFERED',
      'metadata': {
        'type': 0,
        'metadataType': 0,
        'title': title,
        if (posterUrl != null && posterUrl.isNotEmpty)
          'images': [
            {'url': posterUrl}
          ],
      },
    };

    session.sendMessage(CastSession.kNamespaceMedia, {
      'type': 'LOAD',
      'autoPlay': true,
      'currentTime': startTime,
      'media': media,
    });
  }

  Future<void> disconnect() async {
    final session = _activeSession;
    if (session != null) {
      try {
        await CastSessionManager().endSession(session.sessionId);
      } catch (_) {}
    }
    _onDisconnected();
  }

  void _onDisconnected() {
    _activeSession = null;
    _connectedDevice = null;
    _state = CastState.idle;
    notifyListeners();
  }
}
