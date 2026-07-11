import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';

class NearbyMapScreen extends ConsumerWidget {
  const NearbyMapScreen({super.key});

  static const _filters = ['All pets', '🐶 Dogs', '🐱 Cats', '≤ 2 km', '✓ Vaccinated'];

  void _woof(WidgetRef ref, PetProfile pet) {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.woof));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final pets = ref.watch(nearbyPetsProvider).value ?? const <PetProfile>[];
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFDFEEE6), Color(0xFFCFE6DA)])))),
        const Positioned(top: 150, left: 60, child: _Pin(emoji: '🐶', color: Color(0xFFF97316))),
        const Positioned(top: 120, right: 70, child: _Pin(emoji: '🐱', color: Color(0xFFEC4899))),
        const Positioned(top: 320, left: 80, child: _Pin(emoji: '🐕', color: Color(0xFFF0871E))),
        const Positioned(top: 360, right: 96, child: _Pin(emoji: '🐩', color: Color(0xFF6B8DE0))),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => context.go(Routes.discover),
                  child: Container(
                    width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.chevron_left, color: c.text))),
                const SizedBox(width: 12),
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16), boxShadow: c.shadow),
                  child: Text('🔍  Search pets near you',
                    style: PgText.inter(14, FontWeight.w500, color: c.muted)))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) => Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: i == 0 ? c.brand : c.surface,
                    border: i == 0 ? null : Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(_filters[i],
                    style: PgText.inter(12.5, FontWeight.w600, color: i == 0 ? Colors.white : c.text))),
              ),
            ),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 30, offset: Offset(0, -10))]),
              padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${pets.length} pets nearby', style: PgText.poppins(16, FontWeight.w700, color: c.text)),
                  GestureDetector(onTap: () => context.go(Routes.discover),
                    child: Text('Swipe view →', style: PgText.inter(12.5, FontWeight.w700, color: c.brand))),
                ]),
                const SizedBox(height: 12),
                for (final p in pets.take(4)) ...[
                  GestureDetector(
                    onTap: () => showComingSoon(context, 'Pet profile'),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const PgImageSlot(size: 50, circle: true),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                          Text('${p.breed} · ${p.area}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                        ])),
                        GestureDetector(
                          onTap: () => _woof(ref, p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.brand, c.brand2]),
                              borderRadius: BorderRadius.circular(12)),
                            child: Text('Woof!', style: PgText.poppins(12.5, FontWeight.w700, color: Colors.white)))),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Pin extends StatelessWidget {
  final String emoji;
  final Color color;
  const _Pin({required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785,
      child: Container(
        width: 44, height: 44, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22), topRight: Radius.circular(22),
            bottomRight: Radius.circular(22), bottomLeft: Radius.circular(4))),
        child: Transform.rotate(angle: -0.785, child: Text(emoji, style: const TextStyle(fontSize: 18)))),
    );
  }
}
