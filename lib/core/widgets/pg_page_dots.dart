import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgPageDots extends StatelessWidget {
  final int count, index;
  const PgPageDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Row(children: List.generate(count, (i) {
      final active = i == index;
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: AnimatedContainer(
          key: const ValueKey('pg-dot'),
          duration: const Duration(milliseconds: 200),
          width: active ? 24 : 7, height: 7,
          decoration: BoxDecoration(
            color: active ? c.brand : c.border,
            borderRadius: BorderRadius.circular(4)),
        ),
      );
    }));
  }
}
