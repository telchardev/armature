import 'package:shared_preferences/shared_preferences.dart';

import './night_mode_repository.dart';

class SharedPrefsNightModeRepository implements NightModeRepository {
  static const _key = 'night_mode.enabled';

  SharedPrefsNightModeRepository();

  @override
  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
