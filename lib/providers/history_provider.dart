import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';
import '../services/history_service.dart';

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

  factory HistoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HistoryItem(
      animeUrl: data['animeUrl']?.toString() ?? '',
      animeTitle: data['animeTitle']?.toString() ?? '',
      animeImage: data['animeImage']?.toString() ?? '',
      episodeNumber: double.tryParse(data['episodeNumber']?.toString() ?? '1') ?? 1.0,
      episodeTitle: data['episodeTitle']?.toString() ?? '',
      episodeUrl: data['episodeUrl']?.toString() ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
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

  Map<String, dynamic> toFirestore() {
    return {
      'animeUrl': animeUrl,
      'animeTitle': animeTitle,
      'animeImage': animeImage,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'episodeUrl': episodeUrl,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

class HistoryProvider extends ChangeNotifier {
  static const String keyFavorites = 'favorites_list';
  static const String keyHistory = 'watch_history';
  static const String keyRecentEpisodes = 'recent_episodes_log';

  List<AnimeSearchResult> _favorites = [];
  List<HistoryItem> _recentEpisodes = [];
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();
  StreamSubscription<List<HistoryItem>>? _cloudHistorySub;
  String? _syncedUserId;

  List<AnimeSearchResult> get favorites => _favorites;
  List<HistoryItem> get recentEpisodes => _recentEpisodes;
  List<HistoryItem> get history => _continueWatchingList();
  bool get isInitialized => _isInitialized;

  HistoryProvider() {
    init();
  }

  List<HistoryItem> _continueWatchingList() {
    final latestByAnime = <String, HistoryItem>{};
    for (final item in _recentEpisodes) {
      final existing = latestByAnime[item.animeUrl];
      if (existing == null || item.timestamp.isAfter(existing.timestamp)) {
        latestByAnime[item.animeUrl] = item;
      }
    }
    final list = latestByAnime.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();

    final favsRaw = prefs.getStringList(keyFavorites) ?? [];
    _favorites = favsRaw.map((item) => AnimeSearchResult.fromJson(json.decode(item))).toList();

    final recentRaw = prefs.getStringList(keyRecentEpisodes) ?? prefs.getStringList(keyHistory) ?? [];
    _recentEpisodes = recentRaw.map((item) => HistoryItem.fromJson(json.decode(item))).toList();
    _recentEpisodes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _isInitialized = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  Future<void> bindCloudHistory(String? userId) async {
    await _cloudHistorySub?.cancel();
    _cloudHistorySub = null;
    _syncedUserId = userId;

    if (userId == null || userId.isEmpty) return;

    // Esperar a que init() cargue los datos locales antes de mergear
    await _initCompleter.future;

    if (_recentEpisodes.isNotEmpty) {
      try {
        await HistoryService.mergeLocalToCloud(userId, _recentEpisodes);
      } catch (e) {
        debugPrint('[HistoryProvider] mergeLocalToCloud error: $e');
      }
    }

    _cloudHistorySub = HistoryService.watchHistoryStream(userId).listen(
      (cloudItems) {
        if (cloudItems.isEmpty && _recentEpisodes.isNotEmpty) return;
        // Merge: por animeUrl conserva el ítem con timestamp más reciente
        // Evita sobreescribir ítems añadidos localmente que aún no llegaron a Firestore
        final byUrl = <String, HistoryItem>{};
        for (final item in [...cloudItems, ..._recentEpisodes]) {
          final existing = byUrl[item.animeUrl];
          if (existing == null || item.timestamp.isAfter(existing.timestamp)) {
            byUrl[item.animeUrl] = item;
          }
        }
        final merged = byUrl.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _recentEpisodes = merged.take(30).toList();
        _persistRecentLocal();
        notifyListeners();
      },
      onError: (e) => debugPrint('[HistoryProvider] stream error: $e'),
    );
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

  Future<void> _persistRecentLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = _recentEpisodes.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(keyRecentEpisodes, serialized);
    await prefs.setStringList(keyHistory, serialized);
  }

  Future<void> addToHistory({
    required String animeUrl,
    required String animeTitle,
    required String animeImage,
    required double episodeNumber,
    required String episodeTitle,
    required String episodeUrl,
    String? userId,
  }) async {
    _recentEpisodes.removeWhere((item) => item.episodeUrl == episodeUrl);

    final newItem = HistoryItem(
      animeUrl: animeUrl,
      animeTitle: animeTitle,
      animeImage: animeImage,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      episodeUrl: episodeUrl,
      timestamp: DateTime.now(),
    );

    _recentEpisodes.insert(0, newItem);
    if (_recentEpisodes.length > 30) {
      _recentEpisodes = _recentEpisodes.sublist(0, 30);
    }

    await _persistRecentLocal();

    final uid = userId ?? _syncedUserId;
    if (uid != null && uid.isNotEmpty) {
      try {
        await HistoryService.upsertEntry(uid, newItem);
      } catch (e) {
        debugPrint('[HistoryProvider] upsertEntry error: $e');
      }
    }

    notifyListeners();
  }

  double? getLastWatchedEpisode(String animeUrl) {
    HistoryItem? latest;
    for (final item in _recentEpisodes) {
      if (item.animeUrl != animeUrl) continue;
      if (latest == null || item.timestamp.isAfter(latest.timestamp)) {
        latest = item;
      }
    }
    return latest?.episodeNumber;
  }

  Future<void> removeFromHistory(String animeUrl, {String? userId}) async {
    final toRemove = _recentEpisodes.where((item) => item.animeUrl == animeUrl).toList();
    _recentEpisodes.removeWhere((item) => item.animeUrl == animeUrl);
    await _persistRecentLocal();

    final uid = userId ?? _syncedUserId;
    if (uid != null) {
      for (final item in toRemove) {
        await HistoryService.removeEntry(uid, item.episodeUrl);
      }
    }
    notifyListeners();
  }

  Future<void> clearHistory({String? userId}) async {
    _recentEpisodes.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyHistory);
    await prefs.remove(keyRecentEpisodes);

    final uid = userId ?? _syncedUserId;
    if (uid != null && uid.isNotEmpty) {
      await HistoryService.clearAll(uid);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cloudHistorySub?.cancel();
    super.dispose();
  }
}
