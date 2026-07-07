import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgField extends StatelessWidget {
  final String label, value;
  final IconData? icon;
  final bool obscure;
  const PgField({super.key, required this.label, required this.value, this.icon, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: PgText.label(context)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(PgRadius.input),
          ),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c.muted), const SizedBox(width: 11)],
            Text(obscure ? '••••••••' : value,
                style: PgText.inter(14.5, FontWeight.w500, color: c.text)),
          ]),
        ),
      ],
    );
  }
}
