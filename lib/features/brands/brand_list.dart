import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_setup_banner.dart';
import '../../data/models/brand.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';

/// The Home Brands view inside Services: category chips, then brand cards.
/// Lives under the Services category grid, so it has no scaffold of its own.
class BrandList extends ConsumerStatefulWidget {
  const BrandList({super.key});
  @override
  ConsumerState<BrandList> createState() => _BrandListState();
}

class _BrandListState extends ConsumerState<BrandList> {
  BrandCategory? _category;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final profile = ref.watch(currentUserProfileProvider).value;
    final mine = ref.watch(currentBrandProvider);
    final isBrandWithoutListing =
        profile?.role == Role.brand && mine.hasValue && mine.value == null;
    final brandsAsync = ref.watch(brandsProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      if (isBrandWithoutListing)
        PgSetupBanner(emoji: '🛍️', title: 'Set up your brand',
            subtitle: 'Add your products so pet parents can order',
            onTap: () => context.push(Routes.brandSetup)),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _Chip(label: 'All', selected: _category == null,
              onTap: () => setState(() => _category = null)),
          for (final cat in BrandCategory.values)
            _Chip(label: cat.label, selected: _category == cat,
                onTap: () => setState(() => _category = _category == cat ? null : cat)),
        ]),
      ),
      const SizedBox(height: 18),
      Text('Homegrown in Mumbai', style: PgText.sectionHeader(context)),
      const SizedBox(height: 13),
      brandsAsync.when(
        loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('Could not load brands.',
          style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
        data: (brands) {
          // A brand with no products has nothing to order yet.
          final list = brands
              .where((b) => b.products.isNotEmpty && (_category == null || b.category == _category))
              .toList();
          if (list.isEmpty) {
            return Padding(padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No brands here yet — check back soon.',
                style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
          }
          return Column(children: [
            for (final b in list) ...[BrandCard(brand: b), const SizedBox(height: 13)],
          ]);
        },
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.ink : c.surface,
            border: Border.all(color: selected ? c.ink : c.border),
            borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: PgText.inter(12.5, FontWeight.w600,
              color: selected ? Colors.white : c.text)),
        ),
      ),
    );
  }
}

class BrandCard extends StatelessWidget {
  final Brand brand;
  const BrandCard({super.key, required this.brand});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final b = brand;
    return GestureDetector(
      onTap: () => context.push(Routes.brand, extra: b),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
        child: Row(children: [
          PgImageSlot(size: 66, radius: 16, emoji: b.category.emoji, imageUrl: b.logoUrl),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
              if (b.verified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 14, color: c.brand),
              ],
            ]),
            const SizedBox(height: 2),
            Text('${b.category.label} · ${b.area}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 6),
            Text(b.delivery.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w700, color: c.brandDeep)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('from', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            Text('₹${b.fromPrice}', style: PgText.poppins(16, FontWeight.w800, color: c.brand)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
              child: Text('View', style: PgText.poppins(12.5, FontWeight.w700, color: c.brand))),
          ]),
        ]),
      ),
    );
  }
}
