import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novel_history_item.dart';
import '../services/novel_history_service.dart';

class NovelHistoryProvider extends ChangeNotifier {
  static const String _keyHistory = 'novel_history';

  List<NovelHistoryItem> _history = [];
  bool _isInitialized = false;
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
    notifyListeners();
  }

  Future<void> bindCloudHistory(String? userId) async {
    await _cloudSub?.cancel();
    _cloudSub = null;
    _syncedUserId = userId;

    if (userId == null || userId.isEmpty) return;

    // Fusionar historial local a la nube al iniciar sesión
    if (_history.isNotEmpty) {
      await NovelHistoryService.mergeLocalToCloud(userId, _history);
    }

    _cloudSub = NovelHistoryService.historyStream(userId).listen((cloudItems) {
      if (cloudItems.isEmpty && _history.isNotEmpty) return;
      _history = cloudItems;
      _persistLocal();
      notifyListeners();
    });
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
      await NovelHistoryService.upsertEntry(uid, newItem);
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
