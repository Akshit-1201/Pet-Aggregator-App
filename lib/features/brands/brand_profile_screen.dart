import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_moderation_sheet.dart';
import '../../data/models/brand.dart';
import '../../data/models/report.dart';
import '../chat/chat_actions.dart';

/// A Home Brand's page: who they are, what they sell, and one way to order —
/// a chat with the brand. v1 has no cart or checkout (see the design spec).
class BrandProfileScreen extends ConsumerWidget {
  final Brand? brand;
  const BrandProfileScreen({super.key, this.brand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final b = brand;
    if (b == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Brand not found', style: PgText.body(context))),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  // Sized from the real inset so the buttons end above the
                  // card's 40px overlap — see ProProfileScreen for the bug this
                  // avoids on notched iPhones.
                  height: MediaQuery.paddingOf(context).top + 108,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF59E2E), Color(0xFFF0871E)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          _headerButton(Icons.chevron_left, 'Back', () => PgBackScope.pop(context)),
                          const Spacer(),
                          _headerButton(
                            Icons.more_horiz,
                            'Report or block this brand',
                            () => showModerationSheet(
                              context,
                              ref,
                              targetType: ReportTargetType.brand,
                              targetId: b.uid,
                              targetOwnerId: b.uid,
                              targetOwnerName: b.name,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerCard(c, b),
                        const SizedBox(height: 20),
                        Text('About', style: PgText.sectionHeader(context)),
                        const SizedBox(height: 7),
                        Text(
                          b.about.isEmpty ? 'No description yet.' : b.about,
                          style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.6),
                        ),
                        const SizedBox(height: 18),
                        if (b.verified)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                            child: Row(
                              children: [
                                const Text('🛡️', style: TextStyle(fontSize: 18)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pawgo Verified brand',
                                        style: PgText.inter(13, FontWeight.w700, color: c.text),
                                      ),
                                      Text(
                                        'Owner ID confirmed',
                                        style: PgText.inter(12, FontWeight.w400, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            'New brand · not yet Pawgo-verified',
                            style: PgText.inter(12.5, FontWeight.w600, color: c.faint),
                          ),
                        const SizedBox(height: 20),
                        Text('Products', style: PgText.sectionHeader(context)),
                        const SizedBox(height: 10),
                        _productGrid(c, b.products, b.category.emoji),
                        const SizedBox(height: 14),
                        Text(
                          'Orders, payment and delivery are arranged directly with the brand in chat. '
                          'Pawgo Pets is not a party to the sale.',
                          style: PgText.inter(12, FontWeight.w400, color: c.faint, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
            child: GestureDetector(
              onTap: () => openChatWith(context, ref, otherUid: b.uid, otherName: b.name),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 9),
                    Text('Message to order', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Semantics(
      button: true,
      label: label,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white),
      ),
    ),
  );

  Widget _headerCard(PgColors c, Brand b) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.shadow),
    child: Column(
      children: [
        Row(
          children: [
            PgImageSlot(size: 78, radius: 18, emoji: b.category.emoji, imageUrl: b.logoUrl),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          b.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PgText.poppins(19, FontWeight.w800, color: c.text),
                        ),
                      ),
                      if (b.verified) ...[const SizedBox(width: 5), Icon(Icons.verified, size: 16, color: c.brand)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${b.category.label} · ${b.area}', style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: c.border),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _stat(c, b.delivery.short, 'delivery')),
            Container(width: 1, height: 34, color: c.border),
            Expanded(child: _stat(c, '${b.products.length}', b.products.length == 1 ? 'product' : 'products')),
            if (b.sinceYear > 0) ...[
              Container(width: 1, height: 34, color: c.border),
              Expanded(child: _stat(c, 'Since ${b.sinceYear}', 'homegrown')),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _stat(PgColors c, String value, String label) => Column(
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PgText.poppins(15, FontWeight.w800, color: c.text),
      ),
      Text(label, style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
    ],
  );

  Widget _productGrid(PgColors c, List<BrandProduct> products, String emoji) {
    final rows = <Widget>[];
    for (var i = 0; i < products.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _product(c, products[i], emoji)),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < products.length ? _product(c, products[i + 1], emoji) : const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _product(PgColors c, BrandProduct p, String emoji) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.6,
          child: PgImageSlot(radius: 12, emoji: emoji, imageUrl: p.photoUrl),
        ),
        const SizedBox(height: 7),
        Text(
          p.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: PgText.inter(12.5, FontWeight.w600, color: c.text),
        ),
        const SizedBox(height: 1),
        Text('₹${p.price}', style: PgText.poppins(14, FontWeight.w800, color: c.brand)),
      ],
    ),
  );
}
