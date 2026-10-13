import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  ThemeService(this._preferences) {
    _mode = ThemeMode.values.firstWhere(
      (mode) => mode.name == _preferences.getString(_key),
      orElse: () => ThemeMode.light,
    );
    if (_mode == ThemeMode.system) _mode = ThemeMode.light;
  }

  static const _key = 'theme_mode';
  final SharedPreferences _preferences;
  late ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    await _preferences.setString(_key, value.name);
  }
}
