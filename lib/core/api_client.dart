import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';

class ApiClient {
  static const String keyBaseUrl = 'backend_base_url';
  // La URL base NO incluye /api — el cliente lo agrega en cada endpoint
  static const String defaultUrl = 'https://us-central1-serie-938f4.cloudfunctions.net';

  // Obtener la URL base del backend desde SharedPreferences
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String url = prefs.getString(keyBaseUrl) ?? defaultUrl;
    // Migración: quitar /api al final si estaba guardado de una versión anterior
    if (url.endsWith('/api')) {
      url = url.substring(0, url.length - 4);
      await prefs.setString(keyBaseUrl, url);
    }
    return url;
  }

  // Guardar una nueva URL base
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    // Normalizar la URL quitando barra inclinada al final
    String normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    await prefs.setString(keyBaseUrl, normalized);
  }

  // Verificar conexión con el backend
  static Future<bool> testConnection(String testUrl) async {
    try {
      String url = testUrl.trim();
      if (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      // Usamos el endpoint /health que retorna {status: "ok"}
      // Cloud Functions puede tener cold start, damos 12s de timeout
      final uri = Uri.parse('$url/api/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Obtener animes populares/destacados
  static Future<List<AnimeSearchResult>> getPopularAnime({String? domain}) async {
    final baseUrl = await getBaseUrl();
    final queryParams = {
      if (domain != null && domain.isNotEmpty) 'domain': domain,
    };
    final uri = Uri.parse('$baseUrl/api/v1/anime/popular').replace(queryParameters: queryParams);
    
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final resultsList = decoded['data']?['results'] as List?;
      if (resultsList != null) {
        return resultsList.map((item) => AnimeSearchResult.fromJson(item)).toList();
      }
      return [];
    } else {
      final decoded = json.decode(response.body);
      throw Exception(decoded['message'] ?? 'Error al obtener animes populares');
    }
  }

  /// Episodios recién publicados (portada del sitio, p. ej. inicio AnimeAV1).
  static Future<List<LatestPublishedEpisode>> getLatestPublishedEpisodes({String? domain}) async {
    final baseUrl = await getBaseUrl();
    final queryParams = {
      if (domain != null && domain.isNotEmpty) 'domain': domain,
    };
    final uri = Uri.parse('$baseUrl/api/v1/anime/latest-episodes').replace(queryParameters: queryParams);

    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final resultsList = decoded['data']?['results'] as List?;
      if (resultsList != null) {
        return resultsList.map((item) => LatestPublishedEpisode.fromJson(item)).toList();
      }
      return [];
    }
    final decoded = json.decode(response.body);
    throw Exception(decoded['message'] ?? 'Error al cargar episodios recientes');
  }

  // Buscar animes por nombre y proveedor opcional
  static Future<List<AnimeSearchResult>> searchAnime(String query, {String? domain}) async {
    final baseUrl = await getBaseUrl();
    final queryParams = {
      'q': query,
      if (domain != null && domain.isNotEmpty) 'domain': domain,
    };
    final uri = Uri.parse('$baseUrl/api/v1/anime/search').replace(queryParameters: queryParams);
    
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final resultsList = decoded['data']?['results'] as List?;
      if (resultsList != null) {
        return resultsList.map((item) => AnimeSearchResult.fromJson(item)).toList();
      }
      return [];
    } else {
      final decoded = json.decode(response.body);
      throw Exception(decoded['message'] ?? 'Error al buscar animes');
    }
  }

  static Future<Map<String, dynamic>> browseCatalog({
    String? domain,
    String? genre,
    String? year,
    String? type,
    String? status,
    String? query,
    int page = 1,
  }) async {
    final baseUrl = await getBaseUrl();
    final queryParams = <String, String>{
      'page': page.toString(),
      if (domain != null && domain.isNotEmpty) 'domain': domain,
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      if (year != null && year.isNotEmpty) 'year': year,
      if (type != null && type.isNotEmpty) 'type': type,
      if (status != null && status.isNotEmpty) 'status': status,
      if (query != null && query.isNotEmpty) 'q': query,
    };
    final uri = Uri.parse('$baseUrl/api/v1/anime/catalog').replace(queryParameters: queryParams);

    final response = await http.get(uri).timeout(const Duration(seconds: 45));
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      return decoded['data'] as Map<String, dynamic>? ?? {};
    }
    final decoded = json.decode(response.body);
    throw Exception(decoded['message'] ?? 'Error al cargar el catálogo');
  }

  // Obtener información detallada del anime
  static Future<AnimeDetails> getAnimeInfo(String animeUrl) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/v1/anime/info').replace(queryParameters: {'url': animeUrl});
    
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      return AnimeDetails.fromJson(decoded['data'] ?? decoded);
    } else {
      final decoded = json.decode(response.body);
      throw Exception(decoded['message'] ?? 'Error al obtener detalles del anime');
    }
  }

  // Obtener servidores de reproducción y enlaces para un episodio
  static Future<EpisodeLinksResponse> getEpisodeLinks(String episodeUrl) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/v1/anime/episode').replace(queryParameters: {'url': episodeUrl});
    
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      return EpisodeLinksResponse.fromJson(decoded);
    } else {
      final decoded = json.decode(response.body);
      throw Exception(decoded['message'] ?? 'Error al obtener enlaces del episodio');
    }
  }
}
