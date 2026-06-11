import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;

  UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}

class UpdateService {
  static const String githubOwner = 'jhon1466';
  static const String githubRepo = 'Miru';

  // Versión real instalada (leída del paquete, sin hardcodear).
  static String _installedVersion = '';

  /// Carga y cachea la versión instalada. Llamar una vez al iniciar la app.
  static Future<String> loadInstalledVersion() async {
    if (_installedVersion.isNotEmpty) return _installedVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      _installedVersion = info.version; // p. ej. "2.0.14"
    } catch (e) {
      debugPrint('No se pudo leer la versión instalada: $e');
    }
    return _installedVersion;
  }

  /// Getter síncrono para la UI (válido tras [loadInstalledVersion]).
  static String get appVersion =>
      _installedVersion.isNotEmpty ? _installedVersion : '...';

  /// Comprueba si hay una nueva versión disponible en GitHub
  static Future<UpdateInfo> checkForUpdates() async {
    final current = await loadInstalledVersion();
    try {
      final url = Uri.parse('https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Miru-Client-App', // GitHub API requiere User-Agent
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final String tag = data['tag_name'] ?? '';
        final String body = data['body'] ?? 'No hay notas de versión disponibles.';
        
        // Obtener el enlace de descarga del APK del release
        String downloadUrl = '';
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null && assets.isNotEmpty) {
          // Intentar buscar un asset que termine en .apk
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().toLowerCase().endsWith('.apk'),
            orElse: () => null,
          );
          if (apkAsset != null) {
            downloadUrl = apkAsset['browser_download_url'] ?? '';
          }
        }

        // Si no se encuentra un APK en los assets, redirigir a la página de releases
        if (downloadUrl.isEmpty) {
          downloadUrl = data['html_url'] ?? 'https://github.com/$githubOwner/$githubRepo/releases';
        }

        final bool hasNewer = _isNewerVersion(current, tag);

        return UpdateInfo(
          hasUpdate: hasNewer,
          latestVersion: tag,
          downloadUrl: downloadUrl,
          releaseNotes: body,
        );
      } else {
        debugPrint('Error al consultar la API de GitHub: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Excepción al comprobar actualizaciones: $e');
    }

    return UpdateInfo(
      hasUpdate: false,
      latestVersion: appVersion,
      downloadUrl: '',
      releaseNotes: '',
    );
  }

  /// Obtiene las notas del release de la versión actual instalada.
  /// Prueba primero `v{version}`, luego `{version}` como tag name.
  static Future<String?> getReleaseNotesForCurrentVersion() async {
    final v = await loadInstalledVersion();
    final tags = ['v$v', v];
    for (final tag in tags) {
      try {
        final url = Uri.parse(
            'https://api.github.com/repos/$githubOwner/$githubRepo/releases/tags/$tag');
        final response = await http.get(url, headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Miru-Client-App',
        });
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final body = (data['body'] ?? '').toString().trim();
          return body.isEmpty ? null : body;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Compara si la versión de GitHub (latest) es mayor que la actual (current)
  static bool _isNewerVersion(String current, String latest) {
    if (latest.isEmpty) return false;

    // Quitar la 'v' inicial si existe (ej: v1.0.1 -> 1.0.1) y quitar build numbers
    final cleanCurrent = current.replaceAll(RegExp(r'^v'), '').split('+')[0].trim();
    final cleanLatest = latest.replaceAll(RegExp(r'^v'), '').split('+')[0].trim();

    if (cleanCurrent == cleanLatest) return false;

    final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Rellenar con ceros si falta alguna sección (ej: 1.0 -> 1.0.0)
    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (latestParts.length < 3) {
      latestParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    return false;
  }
}
