import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/anime.dart';

/// MonosChinos exige cookies de sesión + CSRF para listar episodios vía AJAX.
class MonosChinosEpisodeService {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static bool isMonosChinosUrl(String url) {
    return url.toLowerCase().contains('monoschinos');
  }

  static String normalizeAnimeUrl(String animeUrl) {
    var trimmed = animeUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!trimmed.startsWith('http')) {
      trimmed = 'https://${trimmed.startsWith('/') ? trimmed.substring(1) : trimmed}';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return trimmed;
    return uri.replace(query: '', fragment: '').toString();
  }

  static Future<List<Episode>> fetchEpisodes(String animeUrl) async {
    final normalized = normalizeAnimeUrl(animeUrl);
    if (normalized.isEmpty) return [];

    var episodes = await _fetchWithHttpClient(normalized);
    if (episodes.length <= 1 && !kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS)) {
      final webEpisodes = await _fetchWithHeadlessWebView(normalized);
      if (webEpisodes.length > episodes.length) {
        episodes = webEpisodes;
      }
    }
    return episodes;
  }

  static Future<List<Episode>> _fetchWithHttpClient(String animeUrl) async {
    final uri = Uri.parse(animeUrl);
    final client = io.HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    client.userAgent = _userAgent;
    final cookieJar = <io.Cookie>[];

    try {
      Future<io.HttpClientResponse> requestPage(
        String url, {
        bool post = false,
        String? csrf,
      }) async {
        final parsed = Uri.parse(url);
        final req = post ? await client.postUrl(parsed) : await client.getUrl(parsed);
        req.headers.set('User-Agent', _userAgent);
        req.headers.set('Accept', post ? 'application/json, text/plain, */*' : 'text/html,application/xhtml+xml');
        if (post) {
          req.headers.set('X-Requested-With', 'XMLHttpRequest');
          req.headers.set('Referer', animeUrl);
          req.headers.set('Origin', '${uri.scheme}://${uri.host}');
          if (csrf != null) {
            req.headers.set('X-CSRF-TOKEN', csrf);
          }
        }
        req.cookies.addAll(cookieJar);
        final res = await req.close().timeout(const Duration(seconds: 10));
        cookieJar.addAll(res.cookies);
        return res;
      }

      final pageResponse = await requestPage(animeUrl);
      if (pageResponse.statusCode < 200 || pageResponse.statusCode >= 400) {
        return [];
      }

      final html = await pageResponse.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final meta = _parsePageMeta(html);
      if (meta == null) return [];

      final slug = _slugFromUrl(animeUrl);
      var verBase = slug.replaceAll(
        RegExp(r'-sub-(espanol|latino|castellano|en-espanol)$', caseSensitive: false),
        '',
      );

      final ajaxResponse = await requestPage(meta.ajaxUrl, post: true, csrf: meta.csrf);
      if (ajaxResponse.statusCode < 200 || ajaxResponse.statusCode >= 300) {
        return [];
      }

      final ajaxBody = await ajaxResponse.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final data = json.decode(ajaxBody) as Map<String, dynamic>;

      final paginateUrl = data['paginate_url']?.toString();
      if (paginateUrl != null) {
        final capResponse = await requestPage('$paginateUrl?p=1', post: true, csrf: meta.csrf);
        if (capResponse.statusCode >= 200 && capResponse.statusCode < 300) {
          final capBody = await capResponse.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
          final capData = json.decode(capBody) as Map<String, dynamic>;
          final caps = capData['caps'] as List?;
          final firstUrl = caps != null && caps.isNotEmpty ? caps.first['url']?.toString() : null;
          if (firstUrl != null) {
            verBase = _verBaseFromCapUrl(firstUrl, verBase);
          }
        }
      }

      return _episodesFromAjaxData(data, uri.host, verBase);
    } catch (e) {
      debugPrint('MonosChinos HTTP episodios: $e');
      return [];
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<Episode>> _fetchWithHeadlessWebView(String animeUrl) async {
    final completer = Completer<List<Episode>>();
    HeadlessInAppWebView? headless;
    var completed = false;

    void finish(List<Episode> list) {
      if (completed) return;
      completed = true;
      if (!completer.isCompleted) completer.complete(list);
    }

    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(animeUrl)),
        initialSettings: InAppWebViewSettings(
          userAgent: _userAgent,
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          loadsImagesAutomatically: false, // Don't load images, much faster!
        ),
        onLoadStop: (controller, _) async {
          try {
            // Check if still on turnstile or gate page by checking title or DOM
            String? title = await controller.getTitle();
            if (completed) return;
            final isCf = await controller.evaluateJavascript(source: '''
              (function() {
                return !!(document.querySelector('#challenge-running') || 
                          document.querySelector('#challenge-stage') || 
                          document.querySelector('#cf-wrapper') || 
                          document.querySelector('.ray_id') ||
                          window.location.href.includes('__cf_chl_tk'));
              })()
            ''');
            if (completed) return;
            if (isCf == true || (title != null && (title.toLowerCase().contains('just a moment') || title.toLowerCase().contains('un momento')))) {
              debugPrint('MonosChinos WebView detected Cloudflare challenge page. Aborting.');
              finish([]);
              return;
            }

            final raw = await controller.evaluateJavascript(source: '''
              (async function() {
                const axUrl = document.querySelector('[data-ajax]')?.getAttribute('data-ajax');
                const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
                if (!axUrl || !csrf) return null;
                const r = await fetch(axUrl, {
                  method: 'POST',
                  headers: {
                    'X-CSRF-TOKEN': csrf,
                    'X-Requested-With': 'XMLHttpRequest',
                    'Accept': 'application/json'
                  },
                  credentials: 'same-origin'
                });
                if (!r.ok) return null;
                const data = await r.json();
                let verBase = '';
                const slug = location.pathname.split('/').filter(Boolean).pop() || '';
                verBase = slug.replace(/-sub-(espanol|latino|castellano|en-espanol)\$/i, '');
                if (data.paginate_url) {
                  try {
                    const capR = await fetch(data.paginate_url + '?p=1', {
                      method: 'POST',
                      headers: {
                        'X-CSRF-TOKEN': csrf,
                        'X-Requested-With': 'XMLHttpRequest',
                        'Accept': 'application/json'
                      },
                      credentials: 'same-origin'
                    });
                    if (capR.ok) {
                      const capData = await capR.json();
                      const u = capData?.caps?.[0]?.url;
                      if (u) {
                        const m = u.match(/\\/ver\\/(.+)-episodio-\\d+/i);
                        if (m) verBase = m[1];
                      }
                    }
                  } catch (e) {}
                }
                return JSON.stringify({ host: location.host, verBase: verBase, eps: data.eps || [] });
              })()
            ''');

            if (completed) return;
            if (raw == null || raw.toString() == 'null') {
              finish([]);
              return;
            }

            String jsonText = raw.toString();
            if (jsonText.startsWith('"') && jsonText.endsWith('"')) {
              jsonText = json.decode(jsonText) as String;
            }

            final parsed = json.decode(jsonText) as Map<String, dynamic>;
            final host = parsed['host']?.toString() ?? Uri.parse(animeUrl).host;
            final verBase = parsed['verBase']?.toString() ?? '';
            final epsRaw = parsed['eps'] as List? ?? [];

            final episodes = <Episode>[];
            for (final rawEp in epsRaw) {
              int? number;
              if (rawEp is num) {
                number = rawEp.toInt();
              } else if (rawEp is Map) {
                number = int.tryParse('${rawEp['num'] ?? rawEp['episodio'] ?? rawEp['number'] ?? ''}');
              }
              if (number == null || number <= 0) continue;
              final base = verBase.isNotEmpty ? verBase : _slugFromUrl(animeUrl).replaceAll(
                    RegExp(r'-sub-(espanol|latino|castellano|en-espanol)$', caseSensitive: false),
                    '',
                  );
              episodes.add(
                Episode(
                  number: number.toDouble(),
                  title: 'Episodio $number',
                  url: 'https://$host/ver/$base-episodio-$number',
                ),
              );
            }
            episodes.sort((a, b) => a.number.compareTo(b.number));
            finish(episodes);
          } catch (e) {
            debugPrint('MonosChinos WebView episodios: $e');
            finish([]);
          }
        },
        onReceivedError: (_, __, ___) => finish([]),
      );

      await headless.run();

      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('MonosChinos WebView timeout');
          completed = true;
          return [];
        },
      );
    } catch (e) {
      debugPrint('MonosChinos WebView init: $e');
      return [];
    } finally {
      await headless?.dispose();
    }
  }

  static _PageMeta? _parsePageMeta(String html) {
    final csrf = RegExp(
      r'''name=["']csrf-token["']\s+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    final axUrl = RegExp(
      r'''data-ajax=["']([^"']*ajax_pagination/\d+)["']''',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (csrf == null || axUrl == null) return null;

    return _PageMeta(csrf: csrf, ajaxUrl: axUrl);
  }

  static List<Episode> _episodesFromAjaxData(
    Map<String, dynamic> data,
    String host,
    String verBase,
  ) {
    final epsRaw = data['eps'] as List?;
    if (epsRaw == null || epsRaw.isEmpty) return [];

    final episodes = <Episode>[];
    for (final raw in epsRaw) {
      int? number;
      if (raw is num) {
        number = raw.toInt();
      } else if (raw is Map) {
        number = int.tryParse('${raw['num'] ?? raw['episodio'] ?? raw['number'] ?? ''}');
      }
      if (number == null || number <= 0) continue;
      episodes.add(
        Episode(
          number: number.toDouble(),
          title: 'Episodio $number',
          url: 'https://$host/ver/$verBase-episodio-$number',
        ),
      );
    }
    episodes.sort((a, b) => a.number.compareTo(b.number));
    return episodes;
  }

  static String _verBaseFromCapUrl(String capUrl, String fallback) {
    final match = RegExp(r'/ver/(.+)-episodio-\d+', caseSensitive: false).firstMatch(capUrl);
    return match?.group(1) ?? fallback;
  }

  static String _slugFromUrl(String url) {
    final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
    final animeIdx = segments.indexOf('anime');
    if (animeIdx >= 0 && animeIdx + 1 < segments.length) {
      return segments[animeIdx + 1];
    }
    return segments.isNotEmpty ? segments.last : '';
  }
}

class _PageMeta {
  final String csrf;
  final String ajaxUrl;

  _PageMeta({
    required this.csrf,
    required this.ajaxUrl,
  });
}
