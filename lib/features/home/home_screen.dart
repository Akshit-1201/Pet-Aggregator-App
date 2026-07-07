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
    final pets = ref.watch(nearbyPetsProvider);
    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            decoration: BoxDecoration(
              color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.location_on, size: 14, color: c.brand),
                  const SizedBox(width: 4),
                  Text('Bandra West, Mumbai', style: PgText.inter(12.5, FontWeight.w600, color: c.muted)),
                ]),
                const SizedBox(height: 5),
                Text('Hey Radhika 👋', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.5)),
                const SizedBox(height: 2),
                Text('6 pets near you today', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
              ])),
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
                  mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
                  children: [
                    _QuickAction(emoji: '🐾', title: 'Discover', subtitle: 'Swipe & Woof nearby pets',
                      bg: null, gradient: [c.brand2, const Color(0xFFF8B45E)], fg: Colors.white,
                      onTap: () => context.go(Routes.discover)),
                    _QuickAction(emoji: '🦮', title: 'Services', subtitle: 'Walkers, sitters, groomers',
                      bg: c.butter, fg: c.text, onTap: () => context.go(Routes.services)),
                    _QuickAction(emoji: '🏡', title: 'Homestay', subtitle: 'Verified boarding hosts',
                      bg: c.lav, fg: c.text, onTap: () => context.go(Routes.services)),
                    _QuickAction(emoji: '💬', title: 'Community', subtitle: 'Ask, share, lost & found',
                      bg: c.mint, fg: c.text, onTap: () => context.go(Routes.community)),
                  ],
                ),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Pets near you', style: PgText.sectionHeader(context)),
                  GestureDetector(
                    onTap: () => context.go(Routes.discover),
                    child: Text('See map →', style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
                ]),
                const SizedBox(height: 13),
                for (final p in pets) ...[
                  PetRow(pet: p, onWoof: () {}),
                  const SizedBox(height: 11),
                ],
                const SizedBox(height: 11),
                Text('Community picks', style: PgText.sectionHeader(context)),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface, border: Border.all(color: c.border),
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
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient == null ? null : LinearGradient(colors: gradient!),
          borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(15, FontWeight.w700, color: fg)),
            Text(subtitle, style: PgText.inter(11.5, FontWeight.w400,
              color: fg.withValues(alpha: 0.8))),
          ]),
        ]),
      ),
    );
  }
}
