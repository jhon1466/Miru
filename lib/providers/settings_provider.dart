import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/adult_content.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyAdult = 'settings_adult_content_enabled';

  bool _adultContentEnabled = false;
  bool _loaded = false;

  bool get adultContentEnabled => _adultContentEnabled;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _adultContentEnabled = prefs.getBool(_keyAdult) ?? false;
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

  List<Map<String, String>> filterProviders(List<Map<String, String>> all) {
    return AdultContent.filterProviders(all, adultEnabled: _adultContentEnabled);
  }
}
