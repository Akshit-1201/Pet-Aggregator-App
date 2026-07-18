import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_chip.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/repositories/providers.dart';
import 'widgets/pet_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final petsAsync = ref.watch(nearbyPetsProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final firstName = (profile?.name ?? '').split(' ').first;
    final greetName = firstName.isEmpty ? 'there' : firstName;

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.location_on, size: 14, color: c.brand),
                  const SizedBox(width: 4),
                  Flexible(child: Text(profile?.area.isNotEmpty == true ? '${profile!.area}, Mumbai' : 'Mumbai',
                      overflow: TextOverflow.ellipsis,
                      style: PgText.inter(12.5, FontWeight.w600, color: c.muted))),
                ]),
                const SizedBox(height: 5),
                Text('Hey $greetName 👋', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.5)),
                const SizedBox(height: 2),
                Text('Pets near you today', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
              ])),
              GestureDetector(
                onTap: () => context.push(Routes.notifications),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13)),
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    Icon(Icons.notifications_none_rounded, size: 20, color: c.text),
                    if (ref.watch(hasUnreadNotificationsProvider))
                      Positioned(top: -2, right: -2, child: Container(
                        key: const ValueKey('notif-dot'), width: 9, height: 9,
                        decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle,
                          border: Border.all(color: c.surface2, width: 1.5)))),
                  ])),
              ),
              GestureDetector(
                onTap: () => context.push(Routes.chatList),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: c.text)),
              ),
              const PgImageSlot(size: 46, circle: true),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.4,
                  children: [
                    _QuickAction(emoji: '🐾', title: 'Discover', subtitle: 'Swipe & Woof nearby pets',
                      bg: null, gradient: [c.brand2, const Color(0xFFF8B45E)], fg: Colors.white,
                      onTap: () => context.go(Routes.discover)),
                    _QuickAction(emoji: '🦮', title: 'Services', subtitle: 'Walkers, sitters, groomers',
                      bg: c.butter, fg: c.text, onTap: () => context.go(Routes.services)),
                    _QuickAction(emoji: '🏡', title: 'Homestay', subtitle: 'Verified boarding hosts',
                      bg: c.lav, fg: c.text, onTap: () => context.push(Routes.homestay)),
                    _QuickAction(emoji: '💬', title: 'Community', subtitle: 'Ask, share, lost & found',
                      bg: c.mint, fg: c.text, onTap: () => context.go(Routes.community)),
                  ],
                ),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Pets near you', style: PgText.sectionHeader(context)),
                  GestureDetector(
                    onTap: () => context.go(Routes.nearby),
                    child: Text('See map →', style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
                ]),
                const SizedBox(height: 13),
                petsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('Could not load nearby pets.',
                      style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
                  data: (pets) => pets.isEmpty
                      ? _EmptyPets(c: c)
                      : Column(children: [
                          for (final p in pets) ...[
                            PetRow(pet: p, onWoof: () {},
                              onTap: () => context.push(Routes.petProfile, extra: p)),
                            const SizedBox(height: 11),
                          ],
                        ]),
                ),
                const SizedBox(height: 11),
                Text('Community picks', style: PgText.sectionHeader(context)),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const PgChip(label: 'Health'),
                    const SizedBox(height: 10),
                    Text('"Best vet in Bandra for vaccinations?"',
                      style: PgText.poppins(15, FontWeight.w600, color: c.text)),
                    const SizedBox(height: 8),
                    Text('24 replies · posted by @dachshund_dad',
                      style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _EmptyPets extends StatelessWidget {
  final PgColors c;
  const _EmptyPets({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('🐾', style: TextStyle(fontSize: 30)),
        const SizedBox(height: 8),
        Text('No pets nearby yet', style: PgText.poppins(15, FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text('Check back soon — new pets join every day.',
          textAlign: TextAlign.center,
          style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color? bg;
  final List<Color>? gradient;
  final Color fg;
  final VoidCallback onTap;
  const _QuickAction({required this.emoji, required this.title, required this.subtitle,
      required this.bg, this.gradient, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg,
          gradient: gradient == null ? null : LinearGradient(colors: gradient!),
          borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: PgText.poppins(15, FontWeight.w700, color: fg)),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: PgText.inter(11.5, FontWeight.w400, color: fg.withValues(alpha: 0.8))),
          ]),
        ]),
      ),
    );
  }
}
