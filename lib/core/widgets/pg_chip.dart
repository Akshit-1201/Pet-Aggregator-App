import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class PgChip extends StatelessWidget {
  final String label;
  final Color? bg, fg;
  const PgChip({super.key, required this.label, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? c.brandSoft,
        borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: PgText.poppins(11, FontWeight.w700, color: fg ?? c.brand)),
    );
  }
}
