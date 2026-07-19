// lib/features/bookings/received_tab.dart  (stub — Task 6 replaces the body)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class ReceivedTab extends ConsumerWidget {
  const ReceivedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text('No bookings for your listing yet.',
                textAlign: TextAlign.center,
                style: PgText.inter(13.5, FontWeight.w400, color: c.muted))));
  }
}
