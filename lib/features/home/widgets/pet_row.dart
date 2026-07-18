import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pg_image_slot.dart';
import '../../../data/models/pet_profile.dart';

class PetRow extends StatelessWidget {
  final PetProfile pet;
  final VoidCallback onWoof;
  final VoidCallback? onTap;
  const PetRow({super.key, required this.pet, required this.onWoof, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
        child: Row(children: [
          PgImageSlot(size: 54, circle: true, imageUrl: pet.photoUrl),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(pet.name, style: PgText.poppins(15, FontWeight.w700, color: c.text)),
              const SizedBox(width: 6),
              Container(width: 7, height: 7,
                decoration: BoxDecoration(color: pet.accentColor, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 2),
            Text('${pet.breed} · ${pet.ageLabel} · ${pet.area}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          GestureDetector(
            onTap: onWoof,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.brand, c.brand2]),
                borderRadius: BorderRadius.circular(13)),
              child: Text('Woof!', style: PgText.poppins(13, FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}
