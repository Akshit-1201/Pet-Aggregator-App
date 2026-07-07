import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgImageSlot extends StatelessWidget {
  final double? size;
  final bool circle;
  final String? emoji;
  final double radius;
  const PgImageSlot({super.key, this.size, this.circle = false, this.emoji, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: c.border),
      ),
      child: Text(emoji ?? '🐾', style: const TextStyle(fontSize: 22)),
    );
  }
}
