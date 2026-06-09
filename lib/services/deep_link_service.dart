import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../core/app_navigator.dart';
import '../models/novel.dart';
import '../screens/detail_screen.dart';
import '../screens/manga_detail_screen.dart';
import '../screens/novel_detail_screen.dart';

class DeepLinkService {
  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _linkSubscription;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) _handleDeepLink(initialLink);
    } catch (e) {
      debugPrint('DeepLinkService getInitialLink error: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) => _handleDeepLink(uri),
      onError: (err) => debugPrint('DeepLinkService stream error: $err'),
    );
  }

  static void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
  }

  // ── Anime provider hosts ──────────────────────────────────────────────────
  static bool _isAnimeProviderUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      return host.contains('animeav1.com') ||
          host.contains('animeflv.net') ||
          host.contains('tioanime.com') ||
          host.contains('jkanime.net') ||
          host.contains('monoschinos') ||
          host.contains('latanime.org') ||
          host.contains('hentaila.com');
    } catch (_) {
      return false;
    }
  }

  // ── Main handler ──────────────────────────────────────────────────────────
  static void _handleDeepLink(Uri uri) async {
    debugPrint('[DeepLink] recibido: $uri');

    final scheme = uri.scheme;

    // ── miru:// o miruapp:// ───────────────────────────────────────────────
    if (scheme == 'miru' || scheme == 'miruapp') {
      final host = uri.host; // "anime", "manga", "novel"
      final params = uri.queryParameters;

      switch (host) {
        case 'anime':
          final animeUrl = params['url'] ?? '';
          final title    = params['title'] ?? 'Cargando...';
          if (animeUrl.isNotEmpty) {
            await _navigate((nav) => nav.push(MaterialPageRoute(
              builder: (_) => DetailScreen(
                animeUrl: Uri.decodeComponent(animeUrl),
                animeTitle: Uri.decodeComponent(title),
              ),
            )));
          }

        case 'manga':
          final id   = params['id'] ?? '';
          final slug = params['slug'] ?? '';
          if (id.isNotEmpty) {
            debugPrint('[DeepLink] abriendo manga id=$id slug=$slug');
            await _navigate((nav) => nav.push(MaterialPageRoute(
              builder: (_) => MangaDetailScreen(
                mangaId: id,
                slug: Uri.decodeComponent(slug),
              ),
            )));
          }

        case 'novel':
          final id    = params['id'] ?? '';
          final url   = params['url'] ?? '';
          final title = params['title'] ?? '';
          if (id.isNotEmpty && url.isNotEmpty) {
            debugPrint('[DeepLink] abriendo novel id=$id');
            final novel = Novel(
              id: id,
              title: Uri.decodeComponent(title),
              url: Uri.decodeComponent(url),
            );
            await _navigate((nav) => nav.push(MaterialPageRoute(
              builder: (_) => NovelDetailScreen(novel: novel),
            )));
          }

        default:
          debugPrint('[DeepLink] host desconocido: $host');
      }
      return;
    }

    // ── http/https → proveedor de anime (compatibilidad legacy) ───────────
    final urlString = uri.toString();
    if (_isAnimeProviderUrl(urlString)) {
      await _navigate((nav) => nav.push(MaterialPageRoute(
        builder: (_) => DetailScreen(
          animeUrl: urlString,
          animeTitle: 'Cargando...',
        ),
      )));
    }
  }

  // ── Navigator helper ──────────────────────────────────────────────────────
  static Future<void> _navigate(void Function(NavigatorState nav) action) async {
    var nav = AppNavigator.key.currentState;
    if (nav == null) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        nav = AppNavigator.key.currentState;
        if (nav != null) break;
      }
    }
    if (nav == null) {
      debugPrint('[DeepLink] NavigatorState no disponible');
      return;
    }
    action(nav);
  }
}
