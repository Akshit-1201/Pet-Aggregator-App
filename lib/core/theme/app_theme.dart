import 'package:flutter/material.dart';
import 'app_colors.dart';

class PgTheme {
  static ThemeData _base(PgColors c, Brightness b) => ThemeData(
        useMaterial3: true,
        brightness: b,
        scaffoldBackgroundColor: c.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: c.brand,
          brightness: b,
          surface: c.surface,
        ),
      );

  static ThemeData light() => _base(PgColors.light, Brightness.light);
  static ThemeData dark() => _base(PgColors.dark, Brightness.dark);
}
