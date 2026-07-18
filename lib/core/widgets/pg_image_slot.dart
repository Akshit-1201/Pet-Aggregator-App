import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PgImageSlot extends StatelessWidget {
  final double? size;
  final bool circle;
  final String? emoji;
  final double radius;
  final String? imageUrl;
  const PgImageSlot({
    super.key, this.size, this.circle = false, this.emoji, this.radius = 20, this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final placeholder = Text(emoji ?? '🐾', style: const TextStyle(fontSize: 22));
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface2,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: c.border),
      ),
      child: hasImage
          ? Image.network(url,
              width: size ?? double.infinity, height: size ?? double.infinity, fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : Center(child: placeholder),
              errorBuilder: (_, _, _) => Center(child: placeholder))
          : placeholder,
    );
  }
}
