import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/homestay_booking.dart';
import '../chat/chat_actions.dart';

class HostAcceptedScreen extends ConsumerWidget {
  final HomestayBooking? booking;
  const HostAcceptedScreen({super.key, this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final b = booking;
    if (b == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No booking')));
    }
    final hostFirst = b.hostName.split(' ').first;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 108, height: 108, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Container(
                width: 78, height: 78, alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
                  shape: BoxShape.circle),
                child: const Text('🏡', style: TextStyle(fontSize: 34)))),
            const SizedBox(height: 20),
            Text('Request sent! 🎉', textAlign: TextAlign.center,
              style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 10),
            Text('$hostFirst will confirm ${b.petName}\'s stay for '
                 '${HomestayBooking.fmtDay(b.checkIn)} – ${HomestayBooking.fmtDay(b.checkOut)} soon.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const PgImageSlot(size: 46, circle: true, emoji: '🏡'),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.hostName, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                  Text('${b.nights} nights · ₹${b.total}',
                    style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                ])),
              ]),
            ),
            const Spacer(),
            SizedBox(width: double.infinity, child: GestureDetector(
              onTap: () => openChatWith(context, ref, otherUid: b.hostId, otherName: b.hostName),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Message $hostFirst',
                  style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => context.go(Routes.home),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Back to home', style: PgText.inter(14, FontWeight.w600, color: c.muted)))),
          ]),
        ),
      ),
    );
  }
}
