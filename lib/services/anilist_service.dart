import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AniListService {
  static const String _keyToken = 'anilist_access_token';
  static const String _keyUsername = 'anilist_username';
  static const String _keyAvatar = 'anilist_avatar';

  static String? _token;
  static String? _username;
  static String? _avatarUrl;

  static String? get token => _token;
  static String? get username => _username;
  static String? get avatarUrl => _avatarUrl;
  static bool get isConnected => _token != null && _token!.isNotEmpty;

  /// Inicializa cargando las credenciales guardadas localmente.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_keyToken);
    _username = prefs.getString(_keyUsername);
    _avatarUrl = prefs.getString(_keyAvatar);
  }

  /// Intenta conectar la cuenta con el token provisto.
  static Future<bool> connect(String rawToken) async {
    // Limpiar el token de posibles espacios o fragmentos de URL
    String cleanToken = rawToken.trim();
    if (cleanToken.contains('access_token=')) {
      final regExp = RegExp(r'access_token=([^&]+)');
      final match = regExp.firstMatch(cleanToken);
      if (match != null) {
        cleanToken = match.group(1)!;
      }
    }

    const query = '''
      query {
        Viewer {
          name
          avatar {
            large
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $cleanToken',
        },
        body: json.encode({'query': query}),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final viewer = body['data']?['Viewer'];
        if (viewer != null) {
          _token = cleanToken;
          _username = viewer['name'];
          _avatarUrl = viewer['avatar']?['large'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyToken, _token!);
          await prefs.setString(_keyUsername, _username!);
          if (_avatarUrl != null) {
            await prefs.setString(_keyAvatar, _avatarUrl!);
          } else {
            await prefs.remove(_keyAvatar);
          }
          return true;
        }
      }
      debugPrint('Error validating AniList token: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Exception validating AniList token: $e');
      return false;
    }
  }

  /// Desconecta y borra credenciales.
  static Future<void> disconnect() async {
    _token = null;
    _username = null;
    _avatarUrl = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyAvatar);
  }

  /// Sincroniza el progreso de visualización de un anime.
  static Future<void> syncWatchProgress(String animeTitle, double episodeNumber) async {
    if (!isConnected) return;

    // 1. Buscar el ID del anime en AniList usando el título
    final mediaId = await _findMediaId(animeTitle);
    if (mediaId == null) {
      debugPrint('AniList Sync: No se encontró anime para el título "$animeTitle"');
      return;
    }

    // 2. Guardar el progreso en la lista del usuario
    await _updateMediaListEntry(mediaId, episodeNumber.toInt());
  }

  static Future<int?> _findMediaId(String title) async {
    const query = '''
      query (\$search: String) {
        Media (search: \$search, type: ANIME) {
          id
          title {
            romaji
            english
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'query': query,
          'variables': {'search': title},
        }),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final id = body['data']?['Media']?['id'];
        if (id != null) {
          return int.tryParse(id.toString());
        }
      }
    } catch (e) {
      debugPrint('AniList Sync: Error searching media by title: $e');
    }
    return null;
  }

  static Future<void> _updateMediaListEntry(int mediaId, int progress) async {
    const mutation = '''
      mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus) {
        SaveMediaListEntry (mediaId: \$mediaId, progress: \$progress, status: \$status) {
          id
          progress
          status
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'query': mutation,
          'variables': {
            'mediaId': mediaId,
            'progress': progress,
            'status': 'CURRENT', // Actualiza a "Viendo" (Watching)
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('AniList Sync: Progreso actualizado correctamente a Ep. $progress para mediaId $mediaId.');
      } else {
        debugPrint('AniList Sync: Falló actualización. Status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('AniList Sync: Excepción al actualizar entrada en AniList: $e');
    }
  }
}
