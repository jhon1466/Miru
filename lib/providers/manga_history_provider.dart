import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga_history_item.dart';
import '../services/manga_history_service.dart';

class MangaHistoryProvider extends ChangeNotifier {
  static const String keyHistory = 'manga_history';

  List<MangaHistoryItem> _history = [];
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();
  StreamSubscription<List<MangaHistoryItem>>? _cloudHistorySub;
  String? _syncedUserId;

  List<MangaHistoryItem> get history => _history;
  bool get isInitialized => _isInitialized;

  MangaHistoryProvider() {
    init();
  }

  Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final recentRaw = prefs.getStringList(keyHistory) ?? [];
    _history = recentRaw.map((item) => MangaHistoryItem.fromJson(json.decode(item))).toList();
    _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _isInitialized = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  Future<void> bindCloudHistory(String? userId) async {
    await _cloudHistorySub?.cancel();
    _cloudHistorySub = null;
    _syncedUserId = userId;

    if (userId == null || userId.isEmpty) return;

    await _initCompleter.future;

    if (_history.isNotEmpty) {
      try {
        await MangaHistoryService.mergeLocalToCloud(userId, _history);
      } catch (e) {
        debugPrint('[MangaHistoryProvider] mergeLocalToCloud error: $e');
      }
    }

    _cloudHistorySub = MangaHistoryService.historyStream(userId).listen(
      (cloudItems) {
        if (cloudItems.isEmpty && _history.isNotEmpty) return;
        final byId = <String, MangaHistoryItem>{};
        for (final item in [...cloudItems, ..._history]) {
          final existing = byId[item.mangaId];
          if (existing == null || item.timestamp.isAfter(existing.timestamp)) {
            byId[item.mangaId] = item;
          }
        }
        final merged = byId.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _history = merged.take(30).toList();
        _persistRecentLocal();
        notifyListeners();
      },
      onError: (e) => debugPrint('[MangaHistoryProvider] stream error: $e'),
    );
  }

  Future<void> _persistRecentLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = _history.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(keyHistory, serialized);
  }

  Future<void> addToHistory({
    required String mangaId,
    required String mangaTitle,
    required String coverUrl,
    required String chapterId,
    required String chapterNumber,
    required int page,
    String? userId,
  }) async {
    _history.removeWhere((item) => item.mangaId == mangaId);

    final newItem = MangaHistoryItem(
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      coverUrl: coverUrl,
      chapterId: chapterId,
      chapterNumber: chapterNumber,
      page: page,
      timestamp: DateTime.now(),
    );

    _history.insert(0, newItem);
    if (_history.length > 30) {
      _history = _history.sublist(0, 30);
    }

    await _persistRecentLocal();

    final uid = userId ?? _syncedUserId;
    if (uid != null && uid.isNotEmpty) {
      try {
        await MangaHistoryService.upsertEntry(uid, newItem);
      } catch (e) {
        debugPrint('[MangaHistoryProvider] upsertEntry error: $e');
      }
    }

    notifyListeners();
  }

  Future<void> removeFromHistory(String mangaId, {String? userId}) async {
    _history.removeWhere((item) => item.mangaId == mangaId);
    await _persistRecentLocal();

    final uid = userId ?? _syncedUserId;
    if (uid != null) {
      await MangaHistoryService.removeEntry(uid, mangaId);
    }
    notifyListeners();
  }

  Future<void> clearHistory({String? userId}) async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyHistory);

    final uid = userId ?? _syncedUserId;
    if (uid != null && uid.isNotEmpty) {
      await MangaHistoryService.clearAll(uid);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cloudHistorySub?.cancel();
    super.dispose();
  }
}
