import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Resultado de extracción: URL directa del video o null si falló
class ExtractResult {
  final String? url;
  final String? error;
  const ExtractResult.ok(this.url) : error = null;
  const ExtractResult.fail(this.error) : url = null;
  bool get success => url != null && url!.isNotEmpty;
}

/// Extractores de URL directa para servidores embed comunes.
/// No requieren WebView — solo HTTP + regex.
class ServerExtractorService {
  static const _timeout = Duration(seconds: 8);
  static const _ua =
      'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/96.0.4664.104 Mobile Safari/537.36';

  /// Intenta extraer la URL directa del video para el [embedUrl] dado.
  /// Devuelve null si no hay extractor para ese servidor.
  static Future<ExtractResult?> extract(String embedUrl) async {
    final lower = embedUrl.toLowerCase();

    if (lower.contains('voe.sx') || lower.contains('voe.com.br')) {
      return _extractVoe(embedUrl);
    }
    if (lower.contains('dood') || lower.contains('doodstream')) {
      return _extractDoodstream(embedUrl);
    }
    if (lower.contains('filemoon') || lower.contains('fmoonembed')) {
      return _extractFilemoon(embedUrl);
    }
    if (lower.contains('mixdrop') || lower.contains('mxdrop')) {
      return _extractMixdrop(embedUrl);
    }
    if (lower.contains('streamtape') || lower.contains('tapecontent')) {
      return _extractStreamtape(embedUrl);
    }
    if (lower.contains('upstream') || lower.contains('upstreamcdn')) {
      return _extractUpstream(embedUrl);
    }
    if (lower.contains('vidhide') || lower.contains('vidguard') ||
        lower.contains('listeamed') || lower.contains('filelions')) {
      return _extractVidguard(embedUrl);
    }
    if (lower.contains('mp4upload')) {
      return _extractMp4upload(embedUrl);
    }
    // Extractor genérico: busca m3u8/mp4 en el HTML de la página
    return _extractGeneric(embedUrl);
  }

  // ── VOE ─────────────────────────────────────────────────────────────────

  static Future<ExtractResult> _extractVoe(String url) async {
    try {
      final html = await _getHtml(url, referer: 'https://voe.sx/');
      if (html == null) return const ExtractResult.fail('no response');

      // Busca: 'hls': 'URL' o "hls": "URL"
      for (final pattern in [
        RegExp(r"""['"]hls['"]\s*:\s*['"]([^'"]+\.m3u8[^'"]*)['"]"""),
        RegExp(r"""sources\s*=\s*\{[^}]*['"]hls['"]\s*:\s*['"]([^'"]+)['"]"""),
        RegExp(r"""hls:\s*['"]([^'"]+\.m3u8[^'"]*)['"]"""),
      ]) {
        final m = pattern.firstMatch(html);
        if (m != null) return ExtractResult.ok(_decodeUrl(m.group(1)!));
      }

      // Busca cualquier m3u8 en el source
      final generic = _findM3u8(html);
      if (generic != null) return ExtractResult.ok(generic);

      return const ExtractResult.fail('m3u8 not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── DOODSTREAM ────────────────────────────────────────────────────────────

  static Future<ExtractResult> _extractDoodstream(String url) async {
    try {
      // Normaliza el dominio
      final uri = Uri.parse(url);
      final base = '${uri.scheme}://${uri.host}';

      final html = await _getHtml(url, referer: base);
      if (html == null) return const ExtractResult.fail('no response');

      // Encuentra el path /pass_md5/ID/
      final passMatch = RegExp(r'/pass_md5/\S+').firstMatch(html);
      if (passMatch == null) return const ExtractResult.fail('pass_md5 not found');

      final passPath = passMatch.group(0)!;
      final passUrl = '$base$passPath';

      // Obtiene la URL base del video
      final passHtml = await _getHtml(passUrl, referer: url);
      if (passHtml == null) return const ExtractResult.fail('pass_md5 fetch failed');

      final videoBase = passHtml.trim();
      if (!videoBase.startsWith('http')) return const ExtractResult.fail('invalid base url');

      // Construye la URL final con token
      final token = passPath.split('/').where((s) => s.isNotEmpty).last;
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rand = _randomStr(10);
      final finalUrl = '$videoBase$rand?token=$token&expiry=$expiry';

      return ExtractResult.ok(finalUrl);
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── FILEMOON ──────────────────────────────────────────────────────────────

  static Future<ExtractResult> _extractFilemoon(String url) async {
    try {
      final html = await _getHtml(url, referer: 'https://filemoon.sx/');
      if (html == null) return const ExtractResult.fail('no response');

      // Filemoon usa JuicyCodes / packed JS
      // Busca eval(function(p,a,c,k,e,d)
      final packed = RegExp(r'eval\(function\(p,a,c,k,e,d\).*?\)</script>',
              dotAll: true)
          .firstMatch(html);

      String unpacked = html;
      if (packed != null) {
        unpacked = _unpackJuice(packed.group(0) ?? html);
      }

      final m3u8 = _findM3u8(unpacked) ?? _findM3u8(html);
      if (m3u8 != null) return ExtractResult.ok(m3u8);

      // Busca file: "URL"
      final fileMatch = RegExp(r'''file\s*:\s*["']([^"']+\.m3u8[^"']*)["']''')
          .firstMatch(unpacked);
      if (fileMatch != null) return ExtractResult.ok(fileMatch.group(1)!);

      return const ExtractResult.fail('m3u8 not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── MIXDROP / MXDROP ─────────────────────────────────────────────────────

  static Future<ExtractResult> _extractMixdrop(String url) async {
    try {
      final html = await _getHtml(url, referer: 'https://mixdrop.co/');
      if (html == null) return const ExtractResult.fail('no response');

      // MDCore.ref y MDCore.wurl
      final wurlMatch = RegExp(r"""MDCore\.wurl\s*=\s*["']([^"']+)["']""")
          .firstMatch(html);
      if (wurlMatch != null) {
        final wurl = wurlMatch.group(1)!;
        return ExtractResult.ok(wurl.startsWith('//') ? 'https:$wurl' : wurl);
      }

      final m3u8 = _findM3u8(html);
      if (m3u8 != null) return ExtractResult.ok(m3u8);

      return const ExtractResult.fail('source not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── STREAMTAPE ────────────────────────────────────────────────────────────

  static Future<ExtractResult> _extractStreamtape(String url) async {
    try {
      final html = await _getHtml(url);
      if (html == null) return const ExtractResult.fail('no response');

      // Streamtape usa concatenación de strings obfuscada
      // Busca: document.getElementById('robotlink').innerHTML = 'BASE' + 'SUFFIX'
      final p1 = RegExp(r"""getElementById\('robotlink'\)\.innerHTML\s*=\s*["']([^"']+)["']""")
          .firstMatch(html);
      final p2 = RegExp(r"""innerHTML\s*=\s*[^+]+\+\s*["']([^"']+)["']""")
          .firstMatch(html);
      if (p1 != null && p2 != null) {
        return ExtractResult.ok('https:${p1.group(1)!}${p2.group(1)!}');
      }

      final m3u8 = _findM3u8(html);
      if (m3u8 != null) return ExtractResult.ok(m3u8);

      return const ExtractResult.fail('source not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── UPSTREAM / UPSTREAMCDN ────────────────────────────────────────────────

  static Future<ExtractResult> _extractUpstream(String url) async {
    try {
      final html = await _getHtml(url);
      if (html == null) return const ExtractResult.fail('no response');

      final m3u8 = _findM3u8(html);
      if (m3u8 != null) return ExtractResult.ok(m3u8);

      final mp4 = _findMp4(html);
      if (mp4 != null) return ExtractResult.ok(mp4);

      return const ExtractResult.fail('source not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── VIDGUARD / VIDHIDE ────────────────────────────────────────────────────

  static Future<ExtractResult> _extractVidguard(String url) async {
    try {
      final html = await _getHtml(url);
      if (html == null) return const ExtractResult.fail('no response');

      final m3u8 = _findM3u8(html);
      if (m3u8 != null) return ExtractResult.ok(m3u8);

      return const ExtractResult.fail('source not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── MP4UPLOAD ─────────────────────────────────────────────────────────────

  static Future<ExtractResult> _extractMp4upload(String url) async {
    try {
      final html = await _getHtml(url);
      if (html == null) return const ExtractResult.fail('no response');

      // src: "URL.mp4"
      final match = RegExp(r'''src\s*:\s*["']([^"']+\.mp4[^"']*)["']''')
          .firstMatch(html);
      if (match != null) return ExtractResult.ok(match.group(1)!);

      final mp4 = _findMp4(html);
      if (mp4 != null) return ExtractResult.ok(mp4);

      return const ExtractResult.fail('mp4 not found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── GENÉRICO ─────────────────────────────────────────────────────────────

  static Future<ExtractResult> _extractGeneric(String url) async {
    try {
      final html = await _getHtml(url);
      if (html == null) return const ExtractResult.fail('no response');

      final m3u8 = _findM3u8(html);
      if (m3u8 != null) return ExtractResult.ok(m3u8);

      final mp4 = _findMp4(html);
      if (mp4 != null) return ExtractResult.ok(mp4);

      return const ExtractResult.fail('no media url found');
    } catch (e) {
      return ExtractResult.fail('$e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<String?> _getHtml(String url, {String? referer}) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _ua,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
          if (referer != null) 'Referer': referer,
        },
      ).timeout(_timeout);
      return response.statusCode == 200 ? response.body : null;
    } catch (e) {
      debugPrint('[Extractor] _getHtml error for $url: $e');
      return null;
    }
  }

  static String? _findM3u8(String html) {
    // Busca URLs m3u8 absolutas
    final match = RegExp(
      r"""https?://[^\s"'<>]+\.m3u8[^\s"'<>]*""",
      caseSensitive: false,
    ).firstMatch(html);
    if (match != null) return match.group(0);

    // Busca paths /m3u8/ que son CDN paths
    final cdnMatch = RegExp(
      r"""https?://[^\s"'<>]+/m3u8/[^\s"'<>]*""",
      caseSensitive: false,
    ).firstMatch(html);
    return cdnMatch?.group(0);
  }

  static String? _findMp4(String html) {
    final match = RegExp(
      r"""https?://[^\s"'<>]+\.mp4[^\s"'<>]*""",
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(0);
  }

  static String _decodeUrl(String url) {
    // Decodifica escapes comunes
    return url.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
  }

  static String _randomStr(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Desempaqueta JS tipo eval(function(p,a,c,k,e,d){...}) (JuicyCodes/P,A,C,K,E,R)
  static String _unpackJuice(String packed) {
    try {
      // Extrae los parámetros del packed JS
      final match = RegExp(
        r"}\s*\('([^']*)',\s*(\d+),\s*(\d+),\s*'([^']*)'.split\('",
      ).firstMatch(packed);
      if (match == null) return packed;

      String p = match.group(1)!;
      final a = int.parse(match.group(2)!);
      final c = int.parse(match.group(3)!);
      final kStr = match.group(4)!;

      // Find the split character (after .split(' '))
      final splitMatch = RegExp(r"\.split\('([^']*)'\)").firstMatch(packed);
      final splitChar = splitMatch?.group(1) ?? '|';
      final k = kStr.split(splitChar);

      String _encode(int e) {
        const base62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        var result = '';
        var n = e;
        do {
          result = base62[n % a] + result;
          n = n ~/ a;
        } while (n > 0);
        return result;
      }

      for (var i = c - 1; i >= 0; i--) {
        final encoded = _encode(i);
        if (i < k.length && k[i].isNotEmpty) {
          p = p.replaceAll(RegExp(r'\b' + encoded + r'\b'), k[i]);
        }
      }
      return p;
    } catch (_) {
      return packed;
    }
  }
}
