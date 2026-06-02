import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../core/app_navigator.dart';
import '../screens/detail_screen.dart';

class DeepLinkService {
  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _linkSubscription;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Handle the initial link (if the app was launched via a link)
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink);
      }
    } catch (e) {
      debugPrint('DeepLinkService getInitialLink error: $e');
    }

    // 2. Subscribe to link events (for warm/foreground state)
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('DeepLinkService stream error: $err');
    });
  }

  static void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
  }

  static bool _isValidAnimeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      // Verificamos si es un host de los proveedores soportados
      return host.contains('animeav1.com') ||
             host.contains('animeflv.net') ||
             host.contains('tioanime.com') ||
             host.contains('jkanime.net') ||
             host.contains('monoschinos2.com') ||
             host.contains('latanime.org') ||
             host.contains('hentaila.com');
    } catch (_) {
      return false;
    }
  }

  static void _handleDeepLink(Uri uri) async {
    String urlString = uri.toString();
    debugPrint('Deep Link recibido: $urlString');

    // Si viene del custom scheme (ej: miru://anime?url=https://...)
    if (uri.scheme == 'miru' || uri.scheme == 'miruapp') {
      final paramUrl = uri.queryParameters['url'];
      if (paramUrl != null && paramUrl.isNotEmpty) {
        urlString = paramUrl;
      }
    }

    if (!_isValidAnimeUrl(urlString)) return;

    // Buscamos el NavigatorState
    var nav = AppNavigator.key.currentState;
    if (nav == null) {
      // Esperamos a que esté listo (similar a NotificationRouting)
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        nav = AppNavigator.key.currentState;
        if (nav != null) break;
      }
    }

    if (nav == null) {
      debugPrint('No se pudo obtener el NavigatorState para procesar el deep link');
      return;
    }

    // Navegar a la pantalla de detalle del anime
    nav.push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          animeUrl: urlString,
          animeTitle: 'Cargando...',
        ),
      ),
    );
  }
}
