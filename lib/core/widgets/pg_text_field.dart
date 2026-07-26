import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PgTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? hint;
  final int maxLines;

  const PgTextField({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Size to the label + box. Forms give this unbounded height so max and
      // min look identical there, but anything that hands it bounded height —
      // an AlertDialog's content, say — gets a field stretched to fill it.
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: PgText.label(context)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(PgRadius.input),
          ),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c.muted), const SizedBox(width: 11)],
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: keyboardType,
                maxLines: maxLines,
                style: PgText.inter(14.5, FontWeight.w500, color: c.text),
                cursorColor: c.brand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: PgText.inter(14.5, FontWeight.w400, color: c.faint),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
