import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgPageDots extends StatelessWidget {
  final int count, index;
  const PgPageDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // Shrink-wrap: a dots indicator must not stretch to fill its parent, or
    // centring it (e.g. the pill on the homestay gallery) produces a full-width
    // bar. No trailing gap after the last dot, so the row is symmetric.
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(count, (i) {
      final active = i == index;
      return Padding(
        padding: EdgeInsets.only(right: i == count - 1 ? 0 : 7),
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
