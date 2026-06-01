import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Caché en disco para respuestas de la API (menos llamadas y menos lecturas en Firebase).
class ApiCacheService {
  static const _prefix = 'miru_api_cache_';
  static const _metaVersionKey = 'miru_cache_content_version';

  static const Duration popularTtl = Duration(hours: 6);
  static const Duration latestTtl = Duration(hours: 2);
  static const Duration catalogTtl = Duration(hours: 3);
  static const Duration searchTtl = Duration(minutes: 45);
  static const Duration scheduleTtl = Duration(hours: 1);

  static Future<int> get contentVersion async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_metaVersionKey) ?? 1;
  }

  static Future<void> bumpContentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getInt(_metaVersionKey) ?? 1) + 1;
    await prefs.setInt(_metaVersionKey, v);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    await bumpContentVersion();
  }

  static Future<T?> getJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson, {
    int? minVersion,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;

    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final expires = DateTime.tryParse(map['expiresAt'] as String? ?? '');
      if (expires == null || DateTime.now().isAfter(expires)) return null;
      if (minVersion != null) {
        final v = map['contentVersion'] as int? ?? 0;
        if (v < minVersion) return null;
      }
      final payload = map['payload'];
      if (payload is Map<String, dynamic>) {
        return fromJson(payload);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<T>?> getJsonList<T>(
    String key,
    T Function(Map<String, dynamic> json) fromItem, {
    int? minVersion,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;

    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final expires = DateTime.tryParse(map['expiresAt'] as String? ?? '');
      if (expires == null || DateTime.now().isAfter(expires)) return null;
      if (minVersion != null) {
        final v = map['contentVersion'] as int? ?? 0;
        if (v < minVersion) return null;
      }
      final payload = map['payload'] as List?;
      if (payload == null) return null;
      return payload
          .whereType<Map>()
          .map((e) => fromItem(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setJson(String key, Map<String, dynamic> payload, Duration ttl) async {
    final prefs = await SharedPreferences.getInstance();
    final version = await contentVersion;
    final envelope = {
      'expiresAt': DateTime.now().add(ttl).toIso8601String(),
      'contentVersion': version,
      'payload': payload,
    };
    await prefs.setString('$_prefix$key', json.encode(envelope));
  }

  static Future<void> setJsonList(
    String key,
    List<Map<String, dynamic>> items,
    Duration ttl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final version = await contentVersion;
    final envelope = {
      'expiresAt': DateTime.now().add(ttl).toIso8601String(),
      'contentVersion': version,
      'payload': items,
    };
    await prefs.setString('$_prefix$key', json.encode(envelope));
  }

  static Future<bool> isStale(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return true;
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final expires = DateTime.tryParse(map['expiresAt'] as String? ?? '');
      return expires == null || DateTime.now().isAfter(expires);
    } catch (_) {
      return true;
    }
  }
}
