import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/pro.dart';
import '../chat/chat_actions.dart';
import '../reviews/reviews_section.dart';

class ProProfileScreen extends ConsumerWidget {
  final Pro? pro;
  const ProProfileScreen({super.key, this.pro});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final p = pro;
    if (p == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Pro not found', style: PgText.body(context))),
      );
    }
    final ratingBadge = p.reviewCount == 0
        ? 'New'
        : '★ ${p.rating.toStringAsFixed(1)} · ${p.reviewCount} reviews';

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFF59E2E), Color(0xFFF0871E)])),
                child: SafeArea(
                  child: Align(alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 40, height: 40, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.chevron_left, color: Colors.white))),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22),
                        boxShadow: c.shadow),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const PgImageSlot(size: 78, radius: 18, emoji: '🧑'),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
                              if (p.verified) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.verified, size: 16, color: c.brand),
                              ],
                            ]),
                            const SizedBox(height: 2),
                            Text('${p.serviceType.label} · ${p.area}',
                              style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                            const SizedBox(height: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                              child: Text(ratingBadge, style: PgText.inter(12.5, FontWeight.w700, color: c.brandDeep))),
                          ])),
                        ]),
                        const SizedBox(height: 16),
                        Container(height: 1, color: c.border),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: _stat('${p.experienceYears} yrs', 'Experience', c)),
                          Container(width: 1, height: 34, color: c.border),
                          Expanded(child: _stat('₹${p.rate}', 'per ${p.unit}', c, brand: true)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('About', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 7),
                    Text(p.bio.isEmpty ? 'No description yet.' : p.bio,
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.6)),
                    const SizedBox(height: 18),
                    // Mirrors the host-profile treatment: say plainly when a pro
                    // has not been vetted rather than implying they have.
                    if (p.verified)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Text('🛡️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Pawgo Verified pro',
                              style: PgText.inter(13, FontWeight.w700, color: c.text)),
                            Text('ID & experience confirmed',
                              style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                          ])),
                        ]),
                      )
                    else
                      Text('New pro · not yet Pawgo-verified',
                        style: PgText.inter(12.5, FontWeight.w600, color: c.faint)),
                    const SizedBox(height: 20),
                    Text('Reviews', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 10),
                    ReviewsSection(targetId: p.uid),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
          child: Row(children: [
            GestureDetector(
              onTap: () => openChatWith(context, ref, otherUid: p.uid, otherName: p.name),
              child: Container(
                width: 54, height: 54, alignment: Alignment.center,
                decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                child: const Text('💬', style: TextStyle(fontSize: 21)))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => context.push(Routes.booking, extra: p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Book · ₹${p.rate}', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String value, String label, PgColors c, {bool brand = false}) => Column(children: [
        Text(value, style: PgText.poppins(17, FontWeight.w800, color: brand ? c.brand : c.text)),
        Text(label, style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]);
}
