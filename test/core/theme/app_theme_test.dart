import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/core/theme/app_colors.dart';

void main() {
  test('light theme uses Pawgo bg as scaffold background', () {
    expect(PgTheme.light().scaffoldBackgroundColor, PgColors.light.bg);
    expect(PgTheme.light().brightness, Brightness.light);
    expect(PgTheme.dark().brightness, Brightness.dark);
  });
}
