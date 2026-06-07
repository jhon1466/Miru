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

  // Media pendiente: se envía cuando el receiver confirme que está listo
  Map<String, dynamic>? _pendingLoad;
  bool _receiverReady = false;

  CastState get state => _state;
  List<CastDevice> get devices => List.unmodifiable(_devices);
  CastDevice? get connectedDevice => _connectedDevice;
  String? get error => _error;
  bool get isConnected => _state == CastState.connected && _activeSession != null;
  bool get isSearching => _state == CastState.searching;
  bool get isConnecting => _state == CastState.connecting;

  // ─── Descubrimiento ──────────────────────────────────────────────────────

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
      debugPrint('[Cast] Encontrados ${_devices.length}: ${_devices.map((d) => d.name).join(', ')}');
    } catch (e) {
      debugPrint('[Cast] Error discovery: $e');
      _error = 'Error buscando dispositivos';
    }

    if (_state == CastState.searching) _state = CastState.idle;
    notifyListeners();
  }

  // ─── Conexión + reproducción ──────────────────────────────────────────────

  /// Conecta al dispositivo y, una vez que el receiver confirma que está listo,
  /// envía automáticamente el video sin depender de un delay fijo.
  Future<bool> connectAndPlay({
    required CastDevice device,
    required String url,
    required String title,
    String? posterUrl,
    double startTime = 0,
  }) async {
    _state = CastState.connecting;
    _connectedDevice = device;
    _receiverReady = false;
    _error = null;
    notifyListeners();

    _pendingLoad = _buildLoad(url: url, title: title, posterUrl: posterUrl, startTime: startTime);

    try {
      final session = await CastSession.connect(
        'miru-${DateTime.now().millisecondsSinceEpoch}',
        device,
        const Duration(seconds: 10),
      );
      _activeSession = session;

      debugPrint('[Cast] Socket OK → ${device.name} (${device.host}:${device.port})');

      // Escucha todos los mensajes del Chromecast
      session.messageStream.listen(_handleMessage);

      // Cambios de estado del socket TLS
      session.stateStream.listen((socketState) {
        debugPrint('[Cast] socketState → $socketState');
        if (socketState == CastSessionState.connected) {
          _state = CastState.connected;
          notifyListeners();
          // Lanza el Default Media Receiver
          debugPrint('[Cast] Enviando LAUNCH CC1AD845…');
          session.sendMessage(CastSession.kNamespaceReceiver, {
            'type': 'LAUNCH',
            'appId': 'CC1AD845',
          });
        } else if (socketState == CastSessionState.closed) {
          debugPrint('[Cast] Socket cerrado');
          _onDisconnected();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[Cast] connectAndPlay error: $e');
      _error = 'No se pudo conectar: $e';
      _state = CastState.idle;
      _connectedDevice = null;
      _activeSession = null;
      _pendingLoad = null;
      notifyListeners();
      return false;
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    debugPrint('[Cast] ← $msg');

    final type = msg['type'] as String?;

    // El receiver confirma que su app está corriendo
    if (type == 'RECEIVER_STATUS') {
      final apps = (msg['status']?['applications'] as List?);
      if (apps != null && apps.isNotEmpty && !_receiverReady) {
        _receiverReady = true;
        final pending = _pendingLoad;
        if (pending != null) {
          _pendingLoad = null;
          debugPrint('[Cast] Receiver listo → enviando LOAD');
          _activeSession?.sendMessage(CastSession.kNamespaceMedia, pending);
        }
      }
    }

    // Confirmación de que el media se está reproduciendo
    if (type == 'MEDIA_STATUS') {
      final items = msg['status'] as List?;
      if (items != null && items.isNotEmpty) {
        final playerState = items[0]['playerState'];
        debugPrint('[Cast] Player state: $playerState');
      }
    }
  }

  // ─── Reenviar video (ya conectado) ───────────────────────────────────────

  Future<void> loadMedia({
    required String url,
    required String title,
    String? posterUrl,
    double startTime = 0,
  }) async {
    final session = _activeSession;
    if (session == null) return;
    final payload = _buildLoad(url: url, title: title, posterUrl: posterUrl, startTime: startTime);
    debugPrint('[Cast] Reenviando LOAD: $url');
    session.sendMessage(CastSession.kNamespaceMedia, payload);
  }

  // ─── Desconexión ─────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    try {
      final s = _activeSession;
      if (s != null) await CastSessionManager().endSession(s.sessionId);
    } catch (_) {}
    _onDisconnected();
  }

  void _onDisconnected() {
    _activeSession = null;
    _connectedDevice = null;
    _pendingLoad = null;
    _receiverReady = false;
    _state = CastState.idle;
    notifyListeners();
  }

  // ─── Helper ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildLoad({
    required String url,
    required String title,
    String? posterUrl,
    double startTime = 0,
  }) {
    final lower = url.toLowerCase();
    final isHls = lower.contains('.m3u8') || lower.contains('/m3u8/') || lower.contains('/hls/');
    return {
      'type': 'LOAD',
      'autoPlay': true,
      'currentTime': startTime,
      'media': {
        'contentId': url,
        'contentType': isHls ? 'application/x-mpegURL' : 'video/mp4',
        'streamType': 'BUFFERED',
        'metadata': {
          'type': 0,
          'metadataType': 0,
          'title': title,
          if (posterUrl != null && posterUrl.isNotEmpty)
            'images': [{'url': posterUrl}],
        },
      },
    };
  }
}
