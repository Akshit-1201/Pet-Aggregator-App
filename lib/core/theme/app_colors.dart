import 'package:flutter/material.dart';

@immutable
class PgColors {
  final Color bg, surface, surface2, text, muted, faint, border;
  final Color brand, brand2, brandDeep, brandSoft, ink, heart, blue;
  final Color peach, lav, butter, mint, purple, pink;
  final List<BoxShadow> shadow, shadowSm;

  const PgColors({
    required this.bg, required this.surface, required this.surface2,
    required this.text, required this.muted, required this.faint,
    required this.border, required this.brand, required this.brand2,
    required this.brandDeep, required this.brandSoft, required this.ink,
    required this.heart, required this.blue, required this.peach,
    required this.lav, required this.butter, required this.mint,
    required this.purple, required this.pink,
    required this.shadow, required this.shadowSm,
  });

  static const light = PgColors(
    bg: Color(0xFFFBF1E8), surface: Color(0xFFFFFFFF), surface2: Color(0xFFFBEDE1),
    text: Color(0xFF1F1A17), muted: Color(0xFF8A7F77), faint: Color(0xFFB7ACA2),
    border: Color(0xFFF1E5D8), brand: Color(0xFFF59E2E), brand2: Color(0xFFF0871E),
    brandDeep: Color(0xFFE07712), brandSoft: Color(0xFFFCE7CC), ink: Color(0xFF211B17),
    heart: Color(0xFFEF4B5E), blue: Color(0xFF6B8DE0), peach: Color(0xFFF4C9B6),
    lav: Color(0xFFE7DBF7), butter: Color(0xFFFBE7B0), mint: Color(0xFFCFEBD9),
    purple: Color(0xFFB79BE8), pink: Color(0xFFEC8FB0),
    shadow: [BoxShadow(color: Color(0x1F78481E), blurRadius: 32, offset: Offset(0, 12))],
    shadowSm: [BoxShadow(color: Color(0x1478481E), blurRadius: 16, offset: Offset(0, 5))],
  );

  static const dark = PgColors(
    bg: Color(0xFF1A1410), surface: Color(0xFF241C16), surface2: Color(0xFF2F251D),
    text: Color(0xFFF7EFE7), muted: Color(0xFFB6A99C), faint: Color(0xFF857667),
    border: Color(0xFF3A2E24), brand: Color(0xFFF59E2E), brand2: Color(0xFFF0871E),
    brandDeep: Color(0xFFE07712), brandSoft: Color(0xFF3D2A12), ink: Color(0xFF0E0A07),
    heart: Color(0xFFEF4B5E), blue: Color(0xFF6B8DE0), peach: Color(0xFF5A3D2C),
    lav: Color(0xFF352A47), butter: Color(0xFF403517), mint: Color(0xFF1E3A2C),
    purple: Color(0xFFB79BE8), pink: Color(0xFFEC8FB0),
    shadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 36, offset: Offset(0, 14))],
    shadowSm: [BoxShadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 5))],
  );
}

extension PgColorsX on BuildContext {
  PgColors get pg =>
      Theme.of(this).brightness == Brightness.dark ? PgColors.dark : PgColors.light;
}
