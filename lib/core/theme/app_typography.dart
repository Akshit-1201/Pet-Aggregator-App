import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class PgText {
  static TextStyle poppins(double size, FontWeight w, {Color? color, double ls = 0}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: color, letterSpacing: ls);

  static TextStyle inter(double size, FontWeight w, {Color? color, double height = 1.0}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color, height: height);

  static TextStyle screenTitle(BuildContext c) =>
      poppins(24, FontWeight.w800, color: c.pg.text, ls: -0.5);
  static TextStyle sectionHeader(BuildContext c) =>
      poppins(16, FontWeight.w700, color: c.pg.text);
  static TextStyle body(BuildContext c) =>
      inter(14.5, FontWeight.w400, color: c.pg.muted, height: 1.55);
  static TextStyle label(BuildContext c) =>
      inter(12.5, FontWeight.w600, color: c.pg.muted);
}
