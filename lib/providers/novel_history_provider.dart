import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novel_history_item.dart';
import '../services/novel_history_service.dart';

class NovelHistoryProvider extends ChangeNotifier {
  static const String _keyHistory = 'novel_history';

  List<NovelHistoryItem> _history = [];
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();
  StreamSubscription<List<NovelHistoryItem>>? _cloudSub;
  String? _syncedUserId;

  List<NovelHistoryItem> get history => _history;
  bool get isInitialized => _isInitialized;

  NovelHistoryProvider() {
    _init();
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyHistory) ?? [];
    _history = raw
        .map((e) {
          try {
            return NovelHistoryItem.fromJson(json.decode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<NovelHistoryItem>()
        .toList();
    _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _isInitialized = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  Future<void> bindCloudHistory(String? userId) async {
    await _cloudSub?.cancel();
    _cloudSub = null;
    _syncedUserId = userId;

    if (userId == null || userId.isEmpty) return;

    // Esperar a que _init() cargue SharedPreferences antes de mergear
    await _initCompleter.future;

    if (_history.isNotEmpty) {
      try {
        await NovelHistoryService.mergeLocalToCloud(userId, _history);
      } catch (e) {
        debugPrint('[NovelHistoryProvider] mergeLocalToCloud error: $e');
      }
    }

    _cloudSub = NovelHistoryService.historyStream(userId).listen(
      (cloudItems) {
        if (cloudItems.isEmpty && _history.isNotEmpty) return;
        // Merge: por novelId conserva el ítem con timestamp más reciente
        final byId = <String, NovelHistoryItem>{};
        for (final item in [...cloudItems, ..._history]) {
          final existing = byId[item.novelId];
          if (existing == null || item.timestamp.isAfter(existing.timestamp)) {
            byId[item.novelId] = item;
          }
        }
        final merged = byId.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _history = merged.take(30).toList();
        _persistLocal();
        notifyListeners();
      },
      onError: (e) => debugPrint('[NovelHistoryProvider] stream error: $e'),
    );
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = _history.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList(_keyHistory, serialized);
  }

  Future<void> addToHistory({
    required String novelId,
    required String novelTitle,
    required String coverUrl,
    required String chapterId,
    required String chapterTitle,
    required double chapterNumber,
    String? userId,
  }) async {
    _history.removeWhere((item) => item.novelId == novelId);

    final newItem = NovelHistoryItem(
      novelId: novelId,
      novelTitle: novelTitle,
      coverUrl: coverUrl,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      chapterNumber: chapterNumber,
      timestamp: DateTime.now(),
    );

    _history.insert(0, newItem);
    if (_history.length > 30) {
      _history = _history.sublist(0, 30);
    }

    await _persistLocal();

    final uid = userId ?? _syncedUserId;
    if (uid != null && uid.isNotEmpty) {
      try {
        await NovelHistoryService.upsertEntry(uid, newItem);
      } catch (e) {
        debugPrint('[NovelHistoryProvider] upsertEntry error: $e');
      }
    }

    notifyListeners();
  }

  Future<void> removeFromHistory(String novelId, {String? userId}) async {
    _history.removeWhere((item) => item.novelId == novelId);
    await _persistLocal();

    final uid = userId ?? _syncedUserId;
    if (uid != null) {
      await NovelHistoryService.removeEntry(uid, novelId);
    }
    notifyListeners();
  }

  Future<void> clearHistory({String? userId}) async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);

    final uid = userId ?? _syncedUserId;
    if (uid != null && uid.isNotEmpty) {
      await NovelHistoryService.clearAll(uid);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cloudSub?.cancel();
    super.dispose();
  }
}
