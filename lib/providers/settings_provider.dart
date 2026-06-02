import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/adult_content.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyAdult = 'settings_adult_content_enabled';
  static const _keyTheme = 'settings_theme_mode';
  static const _keyUpdateNotif = 'settings_update_notifications_enabled';

  bool _adultContentEnabled = false;
  ThemeMode _themeMode = ThemeMode.dark; // Default to dark theme
  bool _updateNotificationsEnabled = true; // Default to true
  bool _loaded = false;

  bool get adultContentEnabled => _adultContentEnabled;
  ThemeMode get themeMode => _themeMode;
  bool get updateNotificationsEnabled => _updateNotificationsEnabled;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _adultContentEnabled = prefs.getBool(_keyAdult) ?? false;
    _updateNotificationsEnabled = prefs.getBool(_keyUpdateNotif) ?? true;
    
    final themeString = prefs.getString(_keyTheme) ?? 'dark';
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == themeString,
      orElse: () => ThemeMode.dark,
    );

    // Sincronizar subscripción a app_updates en base a esta preferencia
    try {
      if (_updateNotificationsEnabled) {
        await FirebaseMessaging.instance.subscribeToTopic('app_updates');
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic('app_updates');
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

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, mode.name);
    notifyListeners();
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

  List<Map<String, String>> filterProviders(List<Map<String, String>> all) {
    return AdultContent.filterProviders(all, adultEnabled: _adultContentEnabled);
  }
}
