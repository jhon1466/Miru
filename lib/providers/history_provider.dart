import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';

class HistoryItem {
  final String animeUrl;
  final String animeTitle;
  final String animeImage;
  final double episodeNumber;
  final String episodeTitle;
  final String episodeUrl;
  final DateTime timestamp;

  HistoryItem({
    required this.animeUrl,
    required this.animeTitle,
    required this.animeImage,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.episodeUrl,
    required this.timestamp,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      animeUrl: json['animeUrl'] ?? '',
      animeTitle: json['animeTitle'] ?? '',
      animeImage: json['animeImage'] ?? '',
      episodeNumber: double.tryParse(json['episodeNumber'].toString()) ?? 1.0,
      episodeTitle: json['episodeTitle'] ?? '',
      episodeUrl: json['episodeUrl'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'animeUrl': animeUrl,
      'animeTitle': animeTitle,
      'animeImage': animeImage,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'episodeUrl': episodeUrl,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class HistoryProvider extends ChangeNotifier {
  static const String keyFavorites = 'favorites_list';
  static const String keyHistory = 'watch_history';

  List<AnimeSearchResult> _favorites = [];
  List<HistoryItem> _history = [];
  bool _isInitialized = false;

  List<AnimeSearchResult> get favorites => _favorites;
  List<HistoryItem> get history => _history;
  bool get isInitialized => _isInitialized;

  HistoryProvider() {
    init();
  }

  // Inicializar cargando desde memoria local
  Future<void> init() async {
    if (_isInitialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    
    // Cargar Favoritos
    final favsRaw = prefs.getStringList(keyFavorites) ?? [];
    _favorites = favsRaw.map((item) {
      return AnimeSearchResult.fromJson(json.decode(item));
    }).toList();

    // Cargar Historial de Reproducción
    final histRaw = prefs.getStringList(keyHistory) ?? [];
    _history = histRaw.map((item) {
      return HistoryItem.fromJson(json.decode(item));
    }).toList();
    
    // Ordenar historial por fecha descendente (más reciente primero)
    _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _isInitialized = true;
    notifyListeners();
  }

  // --- MÉTODOS DE FAVORITOS ---

  bool isFavorite(String url) {
    return _favorites.any((anime) => anime.url == url);
  }

  Future<void> toggleFavorite(AnimeSearchResult anime) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _favorites.indexWhere((item) => item.url == anime.url);

    if (index >= 0) {
      _favorites.removeAt(index);
    } else {
      _favorites.add(anime);
    }

    // Persistir
    final serialized = _favorites.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(keyFavorites, serialized);
    notifyListeners();
  }



  Future<void> toggleFavoriteWithUrl(AnimeDetails details, String animeUrl) async {
    final animeResult = AnimeSearchResult(
      id: details.id,
      title: details.title,
      url: animeUrl,
      image: details.image,
      backdrop: details.backdrop,
      type: details.type,
      score: details.score,
      status: details.status,
      year: details.year,
    );
    await toggleFavorite(animeResult);
  }

  // --- MÉTODOS DE HISTORIAL ---

  Future<void> addToHistory({
    required String animeUrl,
    required String animeTitle,
    required String animeImage,
    required double episodeNumber,
    required String episodeTitle,
    required String episodeUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Eliminar entrada anterior si ya existía el mismo episodio o si queremos actualizar el último episodio visto de este anime
    // En las apps de streaming es mejor tener solo el *último* episodio visto por anime en el historial principal para no saturar.
    // Así "Continuar viendo" muestra una tarjeta por anime con su último episodio.
    _history.removeWhere((item) => item.animeUrl == animeUrl);

    final newItem = HistoryItem(
      animeUrl: animeUrl,
      animeTitle: animeTitle,
      animeImage: animeImage,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      episodeUrl: episodeUrl,
      timestamp: DateTime.now(),
    );

    _history.insert(0, newItem); // Insertar al inicio

    // Limitar historial a los últimos 20 animes
    if (_history.length > 20) {
      _history = _history.sublist(0, 20);
    }

    // Persistir
    final serialized = _history.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(keyHistory, serialized);
    notifyListeners();
  }

  // Obtener el último número de episodio visto para un anime específico
  double? getLastWatchedEpisode(String animeUrl) {
    final index = _history.indexWhere((item) => item.animeUrl == animeUrl);
    if (index >= 0) {
      return _history[index].episodeNumber;
    }
    return null;
  }

  /// Elimina un anime del historial "Continuar viendo".
  Future<void> removeFromHistory(String animeUrl) async {
    final prefs = await SharedPreferences.getInstance();
    _history.removeWhere((item) => item.animeUrl == animeUrl);
    final serialized = _history.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(keyHistory, serialized);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    _history.clear();
    await prefs.remove(keyHistory);
    notifyListeners();
  }
}
