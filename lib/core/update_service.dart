import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  // Constantes de configuración de la app
  static const String appVersion = '1.3.0'; // Versión actual de la aplicación
  static const String githubOwner = 'jhon1466';
  static const String githubRepo = 'Miru';

  /// Comprueba si hay una nueva versión disponible en GitHub
  static Future<UpdateInfo> checkForUpdates() async {
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

        final bool hasNewer = _isNewerVersion(appVersion, tag);

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
