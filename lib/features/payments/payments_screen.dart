import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/booking.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/payment_record.dart';
import '../../data/repositories/providers.dart';

/// The user's payment history — every service booking and homestay stay they've
/// actually paid for, newest first. Each row opens a full receipt.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final services = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final stays =
        ref.watch(myHomestayBookingsProvider).value ??
        const <HomestayBooking>[];
    final records = PaymentRecord.from(services: services, stays: stays);

    return PgBackScope(
      // Cold-start deep link and push-notification tap both `go` here with
      // the stack wiped, but it is also legitimately pushed from Home —
      // upToIfEmpty keeps a real pop when a parent exists and only falls
      // back to Home when there is nothing to pop to.
      upToIfEmpty: Routes.home,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              Builder(
                builder: (ctx) => PgAppBar(
                  title: 'Payments',
                  onBack: () => PgBackScope.pop(ctx),
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? _empty(c)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _row(context, c, records[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    PgColors c,
    PaymentRecord r,
  ) => GestureDetector(
    onTap: () => context.push(Routes.receipt, extra: r),
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              r.kind == PaymentKind.service ? '🐾' : '🏡',
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: PgText.poppins(15, FontWeight.w700, color: c.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  r.subtitle,
                  style: PgText.inter(12.5, FontWeight.w400, color: c.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (PaymentRecord.fmtDateTime(r.paidAtMillis).isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Paid ${PaymentRecord.fmtDateTime(r.paidAtMillis)}',
                    style: PgText.inter(11.5, FontWeight.w400, color: c.faint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${r.total}',
                style: PgText.poppins(15, FontWeight.w800, color: c.text),
              ),
              if (r.isRefunded)
                Text(
                  'Refunded',
                  style: PgText.inter(11.5, FontWeight.w700, color: c.heart),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _empty(PgColors c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🧾', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 10),
        Text(
          'No payments yet',
          style: PgText.poppins(18, FontWeight.w700, color: c.text),
        ),
        const SizedBox(height: 4),
        Text(
          'Bookings you pay for will show up here.',
          style: PgText.inter(13, FontWeight.w400, color: c.muted),
        ),
      ],
    ),
  );
}
