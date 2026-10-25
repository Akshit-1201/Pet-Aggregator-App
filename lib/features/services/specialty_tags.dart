import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/pro.dart';

/// A behaviourist's specialties as small chips. Renders nothing when empty, so
/// every other pro's card is unchanged.
class SpecialtyTags extends StatelessWidget {
  final List<Specialty> specialties;
  final double fontSize;
  const SpecialtyTags({super.key, required this.specialties, this.fontSize = 10.5});

  @override
  Widget build(BuildContext context) {
    if (specialties.isEmpty) return const SizedBox.shrink();
    final c = context.pg;
    return Wrap(spacing: 5, runSpacing: 5, children: [
      for (final s in specialties)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(8)),
          child: Text(s.label, style: PgText.inter(fontSize, FontWeight.w600, color: c.muted)),
        ),
    ]);
  }
}
