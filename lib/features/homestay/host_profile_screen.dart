import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/homestay.dart';
import '../reviews/reviews_section.dart';

class HostProfileScreen extends StatelessWidget {
  final Homestay? homestay;
  const HostProfileScreen({super.key, this.homestay});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final h = homestay;
    if (h == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Home not found', style: PgText.body(context))),
      );
    }
    final chips = <String>['${h.homeType.emoji} ${h.homeType.label}',
      for (final a in h.amenities) '${a.emoji} ${a.label}'];

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Home photo header + back button.
              Stack(children: [
                Container(height: 220, width: double.infinity, color: c.surface2,
                  alignment: Alignment.center,
                  child: Text(h.homeType.emoji, style: const TextStyle(fontSize: 56))),
                Positioned(top: 0, left: 0, child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: GestureDetector(
                      onTap: () => context.canPop() ? context.pop() : null,
                      child: Container(
                        width: 40, height: 40, alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12),
                          boxShadow: c.shadowSm),
                        child: Icon(Icons.chevron_left, color: c.text))),
                  ),
                )),
              ]),
              Transform.translate(
                offset: const Offset(0, -26),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22),
                        boxShadow: c.shadow),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(h.homeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
                              if (h.verified) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.verified, size: 16, color: c.brand),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text('Hosted by ${h.hostName} · ${h.area}',
                              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('₹${h.ratePerNight}', style: PgText.poppins(17, FontWeight.w800, color: c.brand)),
                            Text('/ night', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
                          ]),
                        ]),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final label in chips)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11)),
                              child: Text(label, style: PgText.inter(12, FontWeight.w600, color: c.text))),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('About this home', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 7),
                    Text(h.about.isEmpty ? 'No description yet.' : h.about,
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.6)),
                    const SizedBox(height: 18),
                    if (h.verified)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Text('🛡️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Pawgo Verified host',
                              style: PgText.inter(13, FontWeight.w700, color: c.text)),
                            Text('ID & address confirmed',
                              style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                          ])),
                        ]),
                      )
                    else
                      Text('New host · not yet Pawgo-verified',
                        style: PgText.inter(12.5, FontWeight.w600, color: c.faint)),
                    const SizedBox(height: 20),
                    Text('Recent reviews', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 10),
                    ReviewsSection(targetId: h.uid),
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
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('₹${h.ratePerNight}', style: PgText.poppins(18, FontWeight.w800, color: c.text)),
              Text('/ night', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            ]),
            const SizedBox(width: 16),
            Expanded(child: GestureDetector(
              onTap: () => context.push(Routes.hostRequest, extra: h),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Request to book',
                  style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
          ]),
        ),
      ]),
    );
  }
}
