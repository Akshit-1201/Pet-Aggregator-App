import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const PgToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Container(
        width: 46, height: 27,
        decoration: BoxDecoration(
          color: value ? c.brand : c.border,
          borderRadius: BorderRadius.circular(14)),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(width: 21, height: 21,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        ),
      ),
    );
  }
}
