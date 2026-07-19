// lib/features/bookings/received_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/booking_lifecycle.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/repositories/providers.dart';
import 'booking_dialogs.dart';
import 'my_bookings_screen.dart' show sectionLabel;
import 'phase_chip.dart';

class ReceivedTab extends ConsumerWidget {
  const ReceivedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final stays = ref.watch(receivedStayBookingsProvider).value ?? const <HomestayBooking>[];
    final services = ref.watch(receivedServiceBookingsProvider).value ?? const <Booking>[];
    final now = DateTime.now();

    if (stays.isEmpty && services.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(30),
              child: Text('No bookings for your listing yet.',
                  textAlign: TextAlign.center,
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted))));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (stays.isNotEmpty) ...[
          sectionLabel(c, 'Homestay stays'),
          for (final s in stays)
            if (canDecide(s, now))
              _RequestCard(s)
            else
              _LedgerRow(
                  emoji: '🐾',
                  name: s.petName,
                  detail:
                      '${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights · ₹${s.total}',
                  phase: stayPhase(s, now)),
        ],
        if (services.isNotEmpty) ...[
          sectionLabel(c, 'Service bookings'),
          for (final b in services)
            _LedgerRow(
                emoji: '🐾',
                name: b.petName,
                detail: '${b.serviceType.label} · ${b.dateLabel} · ${b.timeSlot}',
                phase: servicePhase(b, now)),
        ],
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final HomestayBooking s;
  const _RequestCard(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PgImageSlot(size: 46, circle: true, emoji: '🐾'),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Stay request · ${s.petName}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
            const SizedBox(height: 2),
            Text(
                '${HomestayBooking.fmtDay(s.checkIn)} → ${HomestayBooking.fmtDay(s.checkOut)}'
                ' · ${s.nights} nights · ₹${s.total}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          const SizedBox(width: 10),
          const PhaseChip(BookingPhase.pending),
        ]),
        if (s.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('"${s.note}"', style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: GestureDetector(
                  onTap: () async {
                    try {
                      await ref.read(homestayBookingRepositoryProvider).acceptRequest(s.id);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Couldn't update the booking — try again.")));
                    }
                  },
                  child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c.brand, c.brand2]),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Accept',
                          style: PgText.poppins(13.5, FontWeight.w700, color: Colors.white))))),
          const SizedBox(width: 10),
          Expanded(
              child: GestureDetector(
                  onTap: () => confirmAndRun(context,
                      title: 'Decline this request?',
                      message: "This can't be undone.",
                      confirmLabel: 'Decline',
                      action: () =>
                          ref.read(homestayBookingRepositoryProvider).declineRequest(s.id)),
                  child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Decline',
                          style: PgText.poppins(13.5, FontWeight.w600, color: c.text))))),
        ]),
      ]),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final String emoji, name, detail;
  final BookingPhase phase;
  const _LedgerRow(
      {required this.emoji, required this.name, required this.detail, required this.phase});

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
        PhaseChip(phase),
      ]),
    );
  }
}
