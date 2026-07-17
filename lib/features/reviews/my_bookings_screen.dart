import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final services = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final stays = ref.watch(myHomestayBookingsProvider).value ?? const <HomestayBooking>[];
    final rated = ref.watch(myReviewedBookingIdsProvider).value ?? const <String>{};
    final empty = services.isEmpty && stays.isEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PgAppBar(title: 'My Bookings', onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
          Expanded(child: empty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text('No bookings yet — book a service or a homestay to get started.',
                  textAlign: TextAlign.center, style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (services.isNotEmpty) ...[
                    _sectionLabel(c, 'Services'),
                    for (final b in services)
                      _BookingRow(
                        emoji: '🧑', name: b.proName,
                        detail: '${b.serviceType.label} · ${b.dateLabel}',
                        rated: rated.contains(b.id),
                        onRate: () => context.push(Routes.rate, extra: ReviewTarget(
                          type: ReviewTargetType.pro, id: b.proId, name: b.proName,
                          subtitle: '${b.serviceType.label} · ${b.dateLabel}', bookingId: b.id)),
                      ),
                  ],
                  if (stays.isNotEmpty) ...[
                    _sectionLabel(c, 'Homestays'),
                    for (final s in stays)
                      _BookingRow(
                        emoji: '🏡', name: s.homeName,
                        detail: '${s.hostName} · ${s.nights} nights',
                        rated: rated.contains(s.id),
                        onRate: () => context.push(Routes.rate, extra: ReviewTarget(
                          type: ReviewTargetType.homestay, id: s.hostId, name: s.homeName,
                          subtitle: '${s.hostName} · ${s.nights} nights', bookingId: s.id)),
                      ),
                  ],
                ],
              )),
        ]),
      ),
    );
  }

  Widget _sectionLabel(PgColors c, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(text, style: PgText.poppins(14, FontWeight.w700, color: c.muted)),
      );
}

class _BookingRow extends StatelessWidget {
  final String emoji, name, detail;
  final bool rated;
  final VoidCallback onRate;
  const _BookingRow({required this.emoji, required this.name, required this.detail,
      required this.rated, required this.onRate});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        PgImageSlot(size: 46, circle: true, emoji: emoji),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
        const SizedBox(width: 10),
        if (rated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
            child: Text('★ Rated', style: PgText.inter(12.5, FontWeight.w700, color: c.brand)))
        else
          GestureDetector(
            onTap: onRate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [c.brand, c.brand2]), borderRadius: BorderRadius.circular(20)),
              child: Text('Rate', style: PgText.poppins(13, FontWeight.w700, color: Colors.white)))),
      ]),
    );
  }
}
