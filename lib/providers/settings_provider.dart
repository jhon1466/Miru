import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/adult_content.dart';
import '../core/theme.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyAdult = 'settings_adult_content_enabled';
  static const _keyThemeOption = 'settings_theme_option';
  static const _keyUpdateNotif = 'settings_update_notifications_enabled';
  static const _keyAutoplay = 'settings_autoplay_next_episode';
  static const _keyBgDownload = 'settings_background_downloads_enabled';
  static const _keyFavoriteProvider = 'settings_favorite_provider_domain';
  static const _keySeedColor = 'settings_seed_color';

  bool _adultContentEnabled = false;
  AppThemeOption _themeOption = AppThemeOption.light;
  bool _updateNotificationsEnabled = true;
  bool _autoplayNextEpisode = false;
  bool _backgroundDownloadsEnabled = true;
  String _favoriteProviderDomain = '';
  int _seedColorValue = AppTheme.defaultSeedColor.value;
  bool _loaded = false;

  bool get adultContentEnabled => _adultContentEnabled;
  AppThemeOption get themeOption => _themeOption;
  bool get updateNotificationsEnabled => _updateNotificationsEnabled;
  bool get autoplayNextEpisode => _autoplayNextEpisode;
  bool get backgroundDownloadsEnabled => _backgroundDownloadsEnabled;
  String get favoriteProviderDomain => _favoriteProviderDomain;
  Color get seedColor => Color(_seedColorValue);
  bool get isLoaded => _loaded;

  /// ThemeMode efectivo para MaterialApp.
  ThemeMode get themeMode {
    switch (_themeOption) {
      case AppThemeOption.light:
        return ThemeMode.light;
      case AppThemeOption.dark:
        return ThemeMode.dark;
      case AppThemeOption.custom:
        return ThemeMode.system; // sigue el brillo del sistema
    }
  }

  /// Color semilla efectivo: siempre usa el color elegido por el usuario,
  /// independientemente del modo claro/oscuro/sistema.
  Color get effectiveSeedColor => Color(_seedColorValue);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _adultContentEnabled = prefs.getBool(_keyAdult) ?? false;
    _updateNotificationsEnabled = prefs.getBool(_keyUpdateNotif) ?? true;
    _autoplayNextEpisode = prefs.getBool(_keyAutoplay) ?? false;
    _backgroundDownloadsEnabled = prefs.getBool(_keyBgDownload) ?? true;
    _favoriteProviderDomain = prefs.getString(_keyFavoriteProvider) ?? '';
    _seedColorValue = prefs.getInt(_keySeedColor) ?? AppTheme.defaultSeedColor.value;

    final optionStr = prefs.getString(_keyThemeOption) ?? 'light';
    _themeOption = AppThemeOption.values.firstWhere(
      (e) => e.name == optionStr,
      orElse: () => AppThemeOption.light,
    );

    // Migración: si había una clave antigua de ThemeMode, respetarla
    if (!prefs.containsKey(_keyThemeOption)) {
      final legacy = prefs.getString('settings_theme_mode');
      if (legacy == 'dark') _themeOption = AppThemeOption.dark;
    }

    try {
      if (_updateNotificationsEnabled) {
        unawaited(FirebaseMessaging.instance.subscribeToTopic('app_updates'));
      } else {
        unawaited(FirebaseMessaging.instance.unsubscribeFromTopic('app_updates'));
      }
    } catch (e) {
      debugPrint('Error syncing app_updates topic subscription: $e');
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setAdultContentEnabled(bool enabled) async {
    if (_adultContentEnabled == enabled) return;
    _adultContentEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAdult, enabled);
    notifyListeners();
  }

  Future<void> setThemeOption(AppThemeOption option) async {
    if (_themeOption == option) return;
    _themeOption = option;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeOption, option.name);
    notifyListeners();
  }

  /// Alias para compatibilidad con código existente que llama setThemeMode.
  Future<void> setThemeMode(ThemeMode mode) async {
    switch (mode) {
      case ThemeMode.light:
        await setThemeOption(AppThemeOption.light);
      case ThemeMode.dark:
        await setThemeOption(AppThemeOption.dark);
      case ThemeMode.system:
        await setThemeOption(AppThemeOption.custom);
    }
  }

  Future<void> setUpdateNotificationsEnabled(bool enabled) async {
    if (_updateNotificationsEnabled == enabled) return;
    _updateNotificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUpdateNotif, enabled);

    try {
      if (enabled) {
        await FirebaseMessaging.instance.subscribeToTopic('app_updates');
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic('app_updates');
      }
    } catch (e) {
      debugPrint('Error syncing app_updates topic subscription: $e');
    }

    notifyListeners();
  }

  Future<void> setAutoplayNextEpisode(bool value) async {
    if (_autoplayNextEpisode == value) return;
    _autoplayNextEpisode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoplay, value);
    notifyListeners();
  }

  Future<void> setBackgroundDownloadsEnabled(bool value) async {
    if (_backgroundDownloadsEnabled == value) return;
    _backgroundDownloadsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBgDownload, value);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    if (_seedColorValue == color.value) return;
    _seedColorValue = color.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeedColor, color.value);
    notifyListeners();
  }

  Future<void> setFavoriteProviderDomain(String domain) async {
    if (_favoriteProviderDomain == domain) return;
    _favoriteProviderDomain = domain;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFavoriteProvider, domain);
    notifyListeners();
  }

  List<Map<String, String>> filterProviders(List<Map<String, String>> all) {
    return AdultContent.filterProviders(all, adultEnabled: _adultContentEnabled);
  }
}
