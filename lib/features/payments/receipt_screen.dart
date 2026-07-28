import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/payment_record.dart';

/// A single receipt: the line-item breakdown, when it was paid, and the
/// Razorpay payment id. Reads its [PaymentRecord] from the route `extra`.
class ReceiptScreen extends StatelessWidget {
  final PaymentRecord? record;
  const ReceiptScreen({super.key, this.record});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final r = record;
    return PgBackScope(
      upTo: Routes.payments,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              PgAppBar(title: 'Receipt', onBack: () => context.pop()),
              Expanded(
                child: r == null
                    ? Center(
                        child: Text(
                          'Receipt unavailable.',
                          style: PgText.body(context),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                        children: [
                          _header(c, r),
                          const SizedBox(height: 16),
                          _card(c, _lines(context, c, r)),
                          const SizedBox(height: 16),
                          _meta(c, r),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(PgColors c, PaymentRecord r) => Column(
    children: [
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.brandSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          r.kind == PaymentKind.service ? '🐾' : '🏡',
          style: const TextStyle(fontSize: 30),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '₹${r.total}',
        style: PgText.poppins(30, FontWeight.w800, color: c.text),
      ),
      const SizedBox(height: 2),
      Text(
        r.isRefunded ? 'Paid · then refunded' : 'Paid',
        style: PgText.inter(
          13,
          FontWeight.w600,
          color: r.isRefunded ? c.heart : c.brand,
        ),
      ),
      const SizedBox(height: 8),
      Text(r.title, style: PgText.poppins(16, FontWeight.w700, color: c.text)),
      Text(
        r.subtitle,
        style: PgText.inter(12.5, FontWeight.w400, color: c.muted),
      ),
    ],
  );

  List<Widget> _lines(BuildContext context, PgColors c, PaymentRecord r) {
    final rows = <Widget>[];
    final b = r.booking;
    final s = r.stay;
    if (b != null) {
      rows.add(
        _line(
          c,
          '${b.serviceType.label} · ${b.dateLabel}, ${b.timeSlot}',
          '₹${b.rate}',
        ),
      );
      rows.add(_line(c, 'Service fee', '₹${b.fee}'));
    } else if (s != null) {
      rows.add(
        _line(
          c,
          '₹${s.ratePerNight} × ${s.nights} night${s.nights == 1 ? '' : 's'}',
          '₹${s.subtotal}',
        ),
      );
      rows.add(_line(c, 'Service fee', '₹${s.fee}'));
      rows.add(
        _line(
          c,
          '${HomestayBooking.fmtDay(s.checkIn)} → ${HomestayBooking.fmtDay(s.checkOut)}',
          '',
          muted: true,
        ),
      );
    }
    rows.add(const SizedBox(height: 8));
    rows.add(Container(height: 1, color: c.border));
    rows.add(const SizedBox(height: 8));
    rows.add(_line(c, 'Total paid', '₹${r.total}', bold: true));
    if (r.isRefunded) {
      rows.add(_line(c, 'Refunded', '−₹${r.refundAmount}', danger: true));
    }
    return rows;
  }

  Widget _card(PgColors c, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(children: children),
  );

  Widget _line(
    PgColors c,
    String label,
    String value, {
    bool bold = false,
    bool danger = false,
    bool muted = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: PgText.inter(
              muted ? 12 : 13.5,
              bold ? FontWeight.w700 : FontWeight.w500,
              color: muted ? c.faint : c.text,
            ),
          ),
        ),
        if (value.isNotEmpty)
          Text(
            value,
            style: PgText.poppins(
              bold ? 15 : 13.5,
              bold ? FontWeight.w800 : FontWeight.w600,
              color: danger ? c.heart : c.text,
            ),
          ),
      ],
    ),
  );

  Widget _meta(PgColors c, PaymentRecord r) {
    final paidOn = PaymentRecord.fmtDateTime(r.paidAtMillis);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          if (paidOn.isNotEmpty)
            _line(c, r.isRefunded ? 'Last updated' : 'Paid on', paidOn),
          _line(c, 'Payment ID', r.paymentId),
          if (r.isRefunded && (r.stay?.refundId ?? '').isNotEmpty)
            _line(c, 'Refund ID', r.stay!.refundId),
        ],
      ),
    );
  }
}
