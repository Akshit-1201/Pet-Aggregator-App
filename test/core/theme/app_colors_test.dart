import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_colors.dart';

void main() {
  test('light/dark brand + backgrounds match the prototype', () {
    expect(PgColors.light.brand, const Color(0xFFF59E2E));
    expect(PgColors.light.bg, const Color(0xFFFBF1E8));
    expect(PgColors.dark.bg, const Color(0xFF1A1410));
    expect(PgColors.dark.brand, const Color(0xFFF59E2E)); // constant across themes
    expect(PgColors.light.shadow, isNotEmpty);
  });
}
