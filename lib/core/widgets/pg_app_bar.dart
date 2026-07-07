import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  const PgAppBar({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
      child: Row(children: [
        if (onBack != null)
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 42, height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface, border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(PgRadius.iconBtn)),
              child: Icon(Icons.chevron_left, color: c.text)),
          ),
        if (onBack != null) const SizedBox(width: 14),
        Text(title, style: PgText.poppins(19, FontWeight.w700, color: c.text)),
      ]),
    );
  }
}
