import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/homestay.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';

class HomestayListScreen extends ConsumerWidget {
  const HomestayListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final hostsAsync = ref.watch(homestaysProvider);
    final currentHomestay = ref.watch(currentHomestayProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final area = (profile?.area.isNotEmpty ?? false) ? profile!.area : 'Mumbai';
    final isHostWithoutListing = profile?.role == Role.homestayHost &&
        currentHomestay.hasValue && currentHomestay.value == null;

    // Scaffold (not a bare Container): this is a top-level route, so unlike the
    // bottom-nav branches it has no HomeShell Scaffold above it. Without a
    // Material ancestor every Text renders with Flutter's yellow double underline.
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(color: c.peach,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                  child: Container(
                    width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_left, color: Colors.white)),
                ),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Homestay boarding',
                    style: PgText.poppins(22, FontWeight.w800, color: c.text, ls: -0.3)),
                  Text('Verified hosts in $area',
                    style: PgText.inter(12.5, FontWeight.w500, color: c.text)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Text('🗓️', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Add dates · 1 pet',
                    style: PgText.inter(13, FontWeight.w500, color: c.muted))),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                if (isHostWithoutListing)
                  GestureDetector(
                    onTap: () => context.push(Routes.hostSetup),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Text('🏡', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Set up your homestay',
                            style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                          Text('List your home so parents can book boarding',
                            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                        ])),
                        Icon(Icons.chevron_right, color: c.brand),
                      ]),
                    ),
                  ),
                hostsAsync.when(
                  loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Could not load hosts.',
                    style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
                  data: (hosts) {
                    if (hosts.isEmpty) {
                      return Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No hosts nearby yet — check back soon.',
                          style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
                    }
                    return Column(children: [
                      for (final h in hosts) ...[_HostCard(homestay: h), const SizedBox(height: 14)],
                    ]);
                  },
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  final Homestay homestay;
  const _HostCard({required this.homestay});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final h = homestay;
    final rating = h.reviewCount == 0 ? 'New' : '★ ${h.rating.toStringAsFixed(1)}';
    return GestureDetector(
      onTap: () => context.push(Routes.host, extra: h),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20), boxShadow: c.shadowSm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            SizedBox(height: 150, width: double.infinity,
              child: PgImageSlot(radius: 0, emoji: h.homeType.emoji, imageUrl: h.coverPhoto)),
            if (h.verified)
              Positioned(top: 12, left: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20),
                  boxShadow: c.shadowSm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified, size: 13, color: c.brand),
                  const SizedBox(width: 4),
                  Text('Verified host', style: PgText.inter(11.5, FontWeight.w700, color: c.brand)),
                ]))),
          ]),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.homeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: PgText.poppins(15.5, FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text('${h.hostName} · ${h.area}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                const SizedBox(height: 10),
                Row(children: [
                  Text('₹${h.ratePerNight}', style: PgText.poppins(17, FontWeight.w800, color: c.brand)),
                  Text(' / night', style: PgText.inter(12.5, FontWeight.w400, color: c.faint)),
                ]),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                child: Text(rating, style: PgText.inter(12, FontWeight.w700, color: c.brandDeep))),
            ]),
          ),
        ]),
      ),
    );
  }
}
