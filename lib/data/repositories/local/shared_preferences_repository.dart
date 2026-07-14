import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../preferences_repository.dart';

class SharedPreferencesRepository implements PreferencesRepository {
  final SharedPreferences _prefs;
  SharedPreferencesRepository(this._prefs);

  static const _key = 'themeMode';

  @override
  ThemeMode get themeMode {
    switch (_prefs.getString(_key)) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(_key, mode.name);
}
