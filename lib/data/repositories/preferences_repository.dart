import 'package:flutter/material.dart' show ThemeMode;

abstract interface class PreferencesRepository {
  ThemeMode get themeMode;
  Future<void> setThemeMode(ThemeMode mode);
}
