import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pet_aggregator_app/core/theme/app_typography.dart';

void main() {
  // GoogleFonts kicks off an async font load on first use. Disable runtime
  // fetching (no network in tests) and use testWidgets so the fake-async zone
  // abandons the pending load future instead of failing on it.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('poppins helper applies size and weight', (tester) async {
    final s = PgText.poppins(27, FontWeight.w800);
    expect(s.fontSize, 27);
    expect(s.fontWeight, FontWeight.w800);
  });
}
