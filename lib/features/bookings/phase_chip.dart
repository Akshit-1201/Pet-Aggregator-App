import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/booking_lifecycle.dart';

class PhaseChip extends StatelessWidget {
  final BookingPhase phase;
  const PhaseChip(this.phase, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // One-off accents match the notification-feed accent precedent.
    final (Color bg, Color fg) = switch (phase) {
      BookingPhase.upcoming => (c.brandSoft, c.brand),
      BookingPhase.completed => (const Color(0x1A34B27B), const Color(0xFF34B27B)),
      BookingPhase.declined => (const Color(0x1AE5484D), const Color(0xFFE5484D)),
      BookingPhase.pending ||
      BookingPhase.awaitingPayment ||
      BookingPhase.cancelled ||
      BookingPhase.expired => (c.border, c.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(phase.label, style: PgText.inter(11.5, FontWeight.w700, color: fg)),
    );
  }
}
