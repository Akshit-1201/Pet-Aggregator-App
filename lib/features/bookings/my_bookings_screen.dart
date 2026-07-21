// lib/features/bookings/my_bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/booking_lifecycle.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/refund_policy.dart';
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';
import '../../data/services/payment_service.dart';
import 'booking_dialogs.dart';
import 'phase_chip.dart';
import 'received_tab.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  final int initialTab; // 0 = My bookings · 1 = Received
  const MyBookingsScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final hasListing = ref.watch(currentProProvider).value != null ||
        ref.watch(currentHomestayProvider).value != null;
    final tab = hasListing ? _tab : 0;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PgAppBar(
              title: hasListing ? 'Bookings' : 'My Bookings',
              onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
          if (hasListing)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Row(children: [
                _tabChip(c, 'My bookings', 0),
                const SizedBox(width: 8),
                _tabChip(c, 'Received', 1),
              ]),
            ),
          Expanded(child: tab == 1 ? const ReceivedTab() : const _MyBookingsTab()),
        ]),
      ),
    );
  }

  Widget _tabChip(PgColors c, String label, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.brand : c.surface,
          border: selected ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: PgText.inter(13, FontWeight.w600, color: selected ? Colors.white : c.text)),
      ),
    );
  }
}

Widget sectionLabel(PgColors c, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(text, style: PgText.poppins(14, FontWeight.w700, color: c.muted)),
    );

class _MyBookingsTab extends ConsumerWidget {
  const _MyBookingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final services = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final stays = ref.watch(myHomestayBookingsProvider).value ?? const <HomestayBooking>[];
    final rated = ref.watch(myReviewedBookingIdsProvider).value ?? const <String>{};
    final now = DateTime.now();

    if (services.isEmpty && stays.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(30),
              child: Text('No bookings yet — book a service or a homestay to get started.',
                  textAlign: TextAlign.center,
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted))));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (services.isNotEmpty) ...[
          sectionLabel(c, 'Services'),
          for (final b in services)
            _MyBookingRow(
              emoji: '🧑',
              name: b.proName,
              detail: '${b.serviceType.label} · ${b.dateLabel}',
              phase: servicePhase(b, now),
              rated: rated.contains(b.id),
              canCancel: canCancelService(b, now),
              canPay: false,
              onPay: null,
              canCancelPaid: false,
              onCancelPaid: null,
              showContactHost: false,
              onCancel: () => confirmAndRun(context,
                  title: 'Cancel this booking?',
                  message: "This can't be undone.",
                  confirmLabel: 'Cancel booking',
                  action: () => ref.read(bookingRepositoryProvider).cancelBooking(b.id)),
              onRate: () => context.push(Routes.rate,
                  extra: ReviewTarget(
                      type: ReviewTargetType.pro, id: b.proId, name: b.proName,
                      subtitle: '${b.serviceType.label} · ${b.dateLabel}', bookingId: b.id)),
            ),
        ],
        if (stays.isNotEmpty) ...[
          sectionLabel(c, 'Homestays'),
          for (final s in stays)
            _MyBookingRow(
              emoji: '🏡',
              name: s.homeName,
              detail: '${s.hostName} · ${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights'
                  '${s.refundAmount > 0 ? (s.refundId.isNotEmpty ? ' · ₹${s.refundAmount} refunded' : ' · ₹${s.refundAmount} refund pending') : ''}',
              phase: stayPhase(s, now),
              rated: rated.contains(s.id),
              canCancel: canCancelStay(s, now),
              canPay: canPay(s, now),
              canCancelPaid: canCancelPaidStay(s, now),
              showContactHost: stayPhase(s, now) == BookingPhase.upcoming && !canCancelPaidStay(s, now),
              onPay: () => context.push(Routes.homestayPayment, extra: s),
              onCancelPaid: () => _confirmCancelPaid(context, ref, s, now),
              onCancel: () => confirmAndRun(context,
                  title: 'Cancel this booking?',
                  message: "This can't be undone.",
                  confirmLabel: 'Cancel booking',
                  action: () => ref.read(homestayBookingRepositoryProvider).cancelStay(s.id)),
              onRate: () => context.push(Routes.rate,
                  extra: ReviewTarget(
                      type: ReviewTargetType.homestay, id: s.hostId, name: s.homeName,
                      subtitle: '${s.hostName} · ${s.nights} nights', bookingId: s.id)),
            ),
        ],
      ],
    );
  }
}

Future<void> _confirmCancelPaid(
    BuildContext context, WidgetRef ref, HomestayBooking s, DateTime now) async {
  final c = context.pg;
  final refund = refundRupees(s, now);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('Cancel this stay?', style: PgText.poppins(16, FontWeight.w700, color: c.text)),
      content: Text(
          refund > 0
              ? "You'll be refunded ₹$refund of ₹${s.total}. Refunds take 5–7 business days. "
                  "The ₹150 service fee isn't refundable."
              : "Cancellations within 24 hours of check-in aren't refundable — you'll be refunded ₹0.",
          style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Keep', style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(refund > 0 ? 'Cancel & refund' : 'Cancel anyway',
                style: PgText.inter(13.5, FontWeight.w700, color: c.brand))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await ref.read(paymentServiceProvider).refundStay(bookingId: s.id);
    messenger.showSnackBar(SnackBar(
        content: Text(result.refundAmount > 0
            ? 'Stay cancelled. ₹${result.refundAmount} will be refunded in 5–7 days.'
            : (refund > 0
                ? 'Stay cancelled. No refund applied — the 24-hour window had passed.'
                : 'Stay cancelled.'))));
  } on PaymentException catch (e) {
    messenger.showSnackBar(SnackBar(
        // Only 'cancel-failed' is provably "nothing happened", so it is the
        // explicit arm; anything unrecognised falls through to the
        // non-asserting message rather than claiming the stay is untouched.
        content: Text(switch (e.message) {
      'refund-failed' => "Stay cancelled, but the refund didn't go through — contact support.",
      'cancel-failed' => "Couldn't cancel the stay — try again.",
      _ => "We couldn't confirm this cancellation — check My bookings before trying again.",
    })));
  }
}

class _MyBookingRow extends StatelessWidget {
  final String emoji, name, detail;
  final BookingPhase phase;
  final bool rated, canCancel, canPay, showContactHost, canCancelPaid;
  final VoidCallback onRate, onCancel;
  final VoidCallback? onPay;
  final VoidCallback? onCancelPaid;
  const _MyBookingRow(
      {required this.emoji, required this.name, required this.detail, required this.phase,
      required this.rated, required this.canCancel, required this.onRate, required this.onCancel,
      this.canPay = false, this.onPay, this.showContactHost = false,
      this.canCancelPaid = false, this.onCancelPaid});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        PgImageSlot(size: 46, circle: true, emoji: emoji),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          PhaseChip(phase),
          if (rated) ...[
            const SizedBox(height: 6),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('★ Rated',
                    style: PgText.inter(12.5, FontWeight.w700, color: c.brand))),
          ] else if (canRate(phase)) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onRate,
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.brand, c.brand2]),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Rate',
                        style: PgText.poppins(13, FontWeight.w700, color: Colors.white)))),
          ] else if (canPay) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onPay,
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.brand, c.brand2]),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Pay to confirm',
                        style: PgText.poppins(12.5, FontWeight.w700, color: Colors.white)))),
          ],
          if (canCancel) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onCancel,
                child: Text('Cancel',
                    style: PgText.inter(12.5, FontWeight.w600, color: c.muted))),
          ],
          if (canCancelPaid) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onCancelPaid,
                child: Text('Cancel', style: PgText.inter(12.5, FontWeight.w600, color: c.muted))),
          ],
          if (showContactHost) ...[
            const SizedBox(height: 6),
            Text('Contact host to cancel',
                style: PgText.inter(11.5, FontWeight.w500, color: c.faint)),
          ],
        ]),
      ]),
    );
  }
}
