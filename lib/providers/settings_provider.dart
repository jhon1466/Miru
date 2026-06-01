import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/adult_content.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyAdult = 'settings_adult_content_enabled';
  static const _keyTheme = 'settings_theme_mode';

  bool _adultContentEnabled = false;
  ThemeMode _themeMode = ThemeMode.dark; // Default to dark theme
  bool _loaded = false;

  bool get adultContentEnabled => _adultContentEnabled;
  ThemeMode get themeMode => _themeMode;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _adultContentEnabled = prefs.getBool(_keyAdult) ?? false;
    
    final themeString = prefs.getString(_keyTheme) ?? 'dark';
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == themeString,
      orElse: () => ThemeMode.dark,
    );
    
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

  List<Map<String, String>> filterProviders(List<Map<String, String>> all) {
    return AdultContent.filterProviders(all, adultEnabled: _adultContentEnabled);
  }
}
