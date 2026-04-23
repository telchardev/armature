import 'package:shared_preferences/shared_preferences.dart';

import './auth_repository.dart';

class SharedPrefsAuthRepository implements AuthRepository {
  static const _key = 'auth.user';

  SharedPrefsAuthRepository();

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_key);
  }

  @override
  Future<void> save(String name) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_key, name);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_key);
  }
}
