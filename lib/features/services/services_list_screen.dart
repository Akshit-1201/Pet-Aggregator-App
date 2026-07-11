import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/pro.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';

class ServicesListScreen extends ConsumerStatefulWidget {
  const ServicesListScreen({super.key});
  @override
  ConsumerState<ServicesListScreen> createState() => _ServicesListScreenState();
}

class _ServicesListScreenState extends ConsumerState<ServicesListScreen> {
  ServiceType? _filter;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final prosAsync = ref.watch(prosProvider);
    final currentPro = ref.watch(currentProProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final isProWithoutListing =
        profile?.role == Role.servicePro && currentPro.hasValue && currentPro.value == null;

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
            decoration: BoxDecoration(color: c.peach,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Services near you', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
              const SizedBox(height: 3),
              Text('Verified walkers, sitters & groomers',
                style: PgText.inter(13, FontWeight.w500, color: c.text)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                if (isProWithoutListing)
                  GestureDetector(
                    onTap: () => context.go(Routes.proSetup),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Text('🎒', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Set up your services', style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                          Text('Create a listing so parents can book you',
                            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                        ])),
                        Icon(Icons.chevron_right, color: c.brand),
                      ]),
                    ),
                  ),
                Row(children: [
                  for (final t in ServiceType.values)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = _filter == t ? null : t),
                        behavior: HitTestBehavior.opaque,
                        child: Column(children: [
                          Container(
                            width: 56, height: 56, alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _filter == t ? c.brand : c.surface,
                              borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
                            child: Text(t.emoji, style: const TextStyle(fontSize: 24))),
                          const SizedBox(height: 7),
                          Text(t.label.split(' ').last, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: PgText.inter(11.5, FontWeight.w600, color: c.text)),
                        ]),
                      ),
                    ),
                ]),
                const SizedBox(height: 22),
                Text('Recommended', style: PgText.sectionHeader(context)),
                const SizedBox(height: 13),
                prosAsync.when(
                  loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Could not load services.',
                    style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
                  data: (pros) {
                    final list = _filter == null
                        ? pros
                        : pros.where((p) => p.serviceType == _filter).toList();
                    if (list.isEmpty) {
                      return Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No pros nearby yet — check back soon.',
                          style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
                    }
                    return Column(children: [
                      for (final p in list) ...[_ProCard(pro: p), const SizedBox(height: 13)],
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

class _ProCard extends StatelessWidget {
  final Pro pro;
  const _ProCard({required this.pro});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final rating = pro.reviewCount == 0
        ? 'New'
        : '★ ${pro.rating.toStringAsFixed(1)} (${pro.reviewCount})';
    return GestureDetector(
      onTap: () => context.push(Routes.servicePro, extra: pro),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
        child: Row(children: [
          const PgImageSlot(size: 66, radius: 16, emoji: '🧑'),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(pro.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
              const SizedBox(width: 4),
              Icon(Icons.verified, size: 14, color: c.brand),
            ]),
            const SizedBox(height: 2),
            Text('${pro.serviceType.label} · ${pro.experienceYears} yrs',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 6),
            Text(rating, style: PgText.inter(12.5, FontWeight.w700, color: c.brandDeep)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${pro.rate}', style: PgText.poppins(16, FontWeight.w800, color: c.brand)),
            Text('/${pro.unit}', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.push(Routes.booking, extra: pro),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Text('Book', style: PgText.poppins(12.5, FontWeight.w700, color: c.brand)))),
          ]),
        ]),
      ),
    );
  }
}
