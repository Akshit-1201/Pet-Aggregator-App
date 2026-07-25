import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';

class PetProfileDetailScreen extends ConsumerWidget {
  final PetProfile? pet;
  const PetProfileDetailScreen({super.key, this.pet});

  static String _speciesEmoji(Species s) => s == Species.cat ? '🐈' : (s == Species.dog ? '🐕' : '🐾');
  static String _speciesLabel(Species s) => s == Species.cat ? 'Cat' : (s == Species.dog ? 'Dog' : 'Other');
  static String _cap(String s) => s.isEmpty ? '—' : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final p = pet;
    if (p == null) {
      return Scaffold(backgroundColor: c.bg, appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Pet not found', style: PgText.body(context))));
    }
    final isMine = ref.watch(authRepositoryProvider).currentUser?.uid == p.ownerId;
    // Denormalised on the pet: users/{uid} is owner-read-only, so looking the
    // owner up here always came back null and rendered a bare em dash.
    final ownerName = p.ownerName.trim().isEmpty ? '—' : p.ownerName;
    final sexSymbol = p.sex.toLowerCase() == 'female' ? '♀' : '♂';

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(child: ListView(padding: EdgeInsets.zero, children: [
          Stack(children: [
            Container(
              height: 280, width: double.infinity, color: c.surface2, alignment: Alignment.center,
              child: p.photoUrl.isEmpty
                  ? Text(_speciesEmoji(p.species), style: const TextStyle(fontSize: 64))
                  : Image.network(p.photoUrl, height: 280, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Text(_speciesEmoji(p.species), style: const TextStyle(fontSize: 64))),
            ),
            Positioned(top: 0, left: 0, child: SafeArea(child: Padding(
              padding: const EdgeInsets.all(14),
              child: GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: Container(width: 40, height: 40, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), boxShadow: c.shadowSm),
                  child: Icon(Icons.chevron_left, color: c.text)))))),
          ]),
          Transform.translate(offset: const Offset(0, -26), child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.shadow),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: PgText.poppins(22, FontWeight.w800, color: c.text))),
                        const SizedBox(width: 7),
                        Text(sexSymbol, style: PgText.poppins(18, FontWeight.w700, color: c.muted)),
                      ]),
                      const SizedBox(height: 3),
                      Text(PetProfile.detailLine([p.breed, p.ageLabel, p.area]),
                        style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                    ])),
                    if (p.vaccinated)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                        child: Text('✓ Vaccinated', style: PgText.inter(12, FontWeight.w700, color: c.brand))),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _trait(c, _speciesEmoji(p.species), _speciesLabel(p.species))),
                    const SizedBox(width: 9),
                    Expanded(child: _trait(c, sexSymbol, _cap(p.sex))),
                    const SizedBox(width: 9),
                    Expanded(child: _trait(c, p.vaccinated ? '💉' : '❔', p.vaccinated ? 'Vaccinated' : 'Not recorded')),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const PgImageSlot(size: 46, circle: true, emoji: '🙂'),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pet parent', style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
                    Text(ownerName, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                  ])),
                ]),
              ),
            ]))),
        ])),
        if (!isMine)
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
            child: GestureDetector(
              onTap: () async {
                final meUid = ref.read(authRepositoryProvider).currentUser?.uid;
                if (meUid == null) return;
                await ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
                    fromUid: meUid, petId: p.id, ownerId: p.ownerId, direction: SwipeDirection.woof));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text('You woofed ${p.name}! 🐾'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2)));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Send a Woof 👋', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)))),
          ),
      ]),
    );
  }

  Widget _trait(PgColors c, String emoji, String label) => Container(
        padding: const EdgeInsets.all(11), alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(12, FontWeight.w700, color: c.text)),
        ]),
      );
}
