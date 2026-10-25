import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_setup_banner.dart';
import '../../data/models/pro.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';
import '../brands/brand_list.dart';
import '../home/home_shell.dart';
import 'specialty_tags.dart';

class ServicesListScreen extends ConsumerStatefulWidget {
  const ServicesListScreen({super.key});
  @override
  ConsumerState<ServicesListScreen> createState() => _ServicesListScreenState();
}

class _ServicesListScreenState extends ConsumerState<ServicesListScreen> {
  ServiceType? _filter;

  /// Home Brands is a sixth category tile but not a [ServiceType] — brands are
  /// a catalogue, not a bookable pro — so it is tracked on its own.
  bool _brands = false;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final profile = ref.watch(currentUserProfileProvider).value;
    final currentPro = ref.watch(currentProProvider);
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // A tab root has no PgBackScope — HomeShell owns its back.
              // goBranch(homeBranch) is the same switch hardware back takes.
              GestureDetector(
                onTap: () => StatefulNavigationShell.maybeOf(context)?.goBranch(HomeShell.homeBranch),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(PgRadius.iconBtn)),
                  child: Icon(Icons.chevron_left, color: c.text)),
              ),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Services near you', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
                const SizedBox(height: 3),
                Text('Walkers, sitters, groomers, trainers & more',
                  style: PgText.inter(13, FontWeight.w500, color: c.text)),
              ])),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                if (isProWithoutListing && !_brands)
                  PgSetupBanner(emoji: '🎒', title: 'Set up your services',
                      subtitle: 'Create a listing so parents can book you',
                      onTap: () => context.push(Routes.proSetup)),
                _categoryGrid(c),
                const SizedBox(height: 4),
                if (_brands) const BrandList() else _pros(c),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// Six tiles, three to a row — a single row of six doesn't fit a phone.
  Widget _categoryGrid(PgColors c) {
    final tiles = <Widget>[
      for (final t in ServiceType.values)
        _CategoryTile(
          emoji: t.emoji, label: t.label.split(' ').last,
          selected: !_brands && _filter == t,
          onTap: () => setState(() {
            _brands = false;
            _filter = _filter == t ? null : t;
          }),
        ),
      _CategoryTile(
        emoji: '🛍️', label: 'Home Brands', selected: _brands,
        onTap: () => setState(() {
          _brands = !_brands;
          _filter = null;
        }),
      ),
    ];
    return Column(children: [
      for (var i = 0; i < tiles.length; i += 3) ...[
        if (i > 0) const SizedBox(height: 10),
        Row(children: [
          for (var j = i; j < i + 3; j++) ...[
            if (j > i) const SizedBox(width: 10),
            Expanded(child: j < tiles.length ? tiles[j] : const SizedBox.shrink()),
          ],
        ]),
      ],
    ]);
  }

  Widget _pros(PgColors c) {
    final prosAsync = ref.watch(prosProvider);
    final filter = _filter;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Text(filter == ServiceType.behaviourist ? 'Pet behaviourists' : 'Recommended',
          style: PgText.sectionHeader(context)),
      const SizedBox(height: 13),
      prosAsync.when(
        loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('Could not load services.',
          style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
        data: (pros) {
          final list = filter == null ? pros : pros.where((p) => p.serviceType == filter).toList();
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
    ]);
  }
}

class _CategoryTile extends StatelessWidget {
  final String emoji, label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTile({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Semantics(
      button: true, selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 11, 6, 9),
          decoration: BoxDecoration(
            color: selected ? c.brand : c.surface,
            borderRadius: BorderRadius.circular(16), boxShadow: c.shadowSm),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(11.5, FontWeight.w600, color: selected ? Colors.white : c.text)),
          ]),
        ),
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
              if (pro.verified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 14, color: c.brand),
              ],
            ]),
            const SizedBox(height: 2),
            Text('${pro.serviceType.label} · ${pro.experienceYears} yrs',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 6),
            Text(rating, style: PgText.inter(12.5, FontWeight.w700, color: c.brandDeep)),
            if (pro.shownSpecialties.isNotEmpty) ...[
              const SizedBox(height: 6),
              SpecialtyTags(specialties: pro.shownSpecialties),
            ],
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
