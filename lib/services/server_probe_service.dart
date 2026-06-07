import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Resultado del escaneo de un servidor
enum ProbeResult { native, webview, unknown }

class ServerProbeService {
  static const _timeout = Duration(seconds: 5);

  /// Prueba si una URL se puede reproducir en el reproductor nativo.
  /// Hace HEAD (o GET parcial) y verifica Content-Type.
  /// Verificación rápida sin red (solo patrones de URL)
  static ProbeResult quickCheck(String url) {
    if (_isStaticallyNative(url)) return ProbeResult.native;
    if (_isStaticallyEmbed(url)) return ProbeResult.webview;
    return ProbeResult.unknown;
  }

  static Future<ProbeResult> probe(String url) async {
    if (url.isEmpty) return ProbeResult.unknown;

    // Verificación estática rápida antes de hacer red
    if (_isStaticallyNative(url)) return ProbeResult.native;
    if (_isStaticallyEmbed(url)) return ProbeResult.webview;

    try {
      final uri = Uri.parse(url);
      final client = http.Client();
      try {
        final request = http.Request('HEAD', uri)
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/96.0'
          ..followRedirects = true
          ..maxRedirects = 5;

        final streamed = await client.send(request).timeout(_timeout);
        final contentType = streamed.headers['content-type'] ?? '';
        await streamed.stream.drain<void>().catchError((_) {});
        return _contentTypeIsNative(contentType)
            ? ProbeResult.native
            : ProbeResult.webview;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[Probe] $url → error: $e');
      return ProbeResult.unknown;
    }
  }

  /// Escanea una lista de URLs en paralelo y devuelve un mapa url→resultado.
  static Future<Map<String, ProbeResult>> probeAll(List<String> urls) async {
    final results = await Future.wait(
      urls.map((url) async {
        final result = await probe(url);
        return MapEntry(url, result);
      }),
    );
    return Map.fromEntries(results);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static bool _contentTypeIsNative(String ct) {
    final lower = ct.toLowerCase();
    return lower.startsWith('video/') ||
        lower.startsWith('audio/') ||
        lower.contains('application/x-mpegurl') ||
        lower.contains('application/vnd.apple.mpegurl') ||
        lower.contains('application/octet-stream');
  }

  static bool _isStaticallyNative(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.m3u8') ||
        lower.contains('/m3u8/') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('/get_video?') ||
        lower.contains('googleusercontent.com');
  }

  static bool _isStaticallyEmbed(String url) {
    final lower = url.toLowerCase();
    const embedDomains = [
      'fembed.com',
      'doodstream.com/e/',
      'streamwish.to/e/',
      'voe.sx/e/',
      'streamtape.com/e/',
      'mixdrop.co/e/',
      'filemoon.sx/e/',
      'streamlare.com/e/',
      'vidstream.pro',
      'uqload.co',
      'sendvid.com',
    ];
    return embedDomains.any((d) => lower.contains(d));
  }
}
