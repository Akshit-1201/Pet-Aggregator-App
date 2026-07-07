import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  const PgPrimaryButton(
      {super.key, required this.label, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [c.brand, c.brand2],
          ),
          borderRadius: BorderRadius.circular(PgRadius.button),
          boxShadow: [
            BoxShadow(color: c.brand.withValues(alpha: 0.25),
                blurRadius: 30, offset: const Offset(0, 14)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
            Text(label, style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class PgGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const PgGhostButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label,
          style: PgText.inter(14, FontWeight.w600, color: context.pg.muted)),
    );
  }
}
