import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/providers.dart';
import '../../data/services/payment_service.dart';

enum _PayPhase { idle, opening, verifying }

class PaymentScreen extends ConsumerStatefulWidget {
  final Booking? booking;
  const PaymentScreen({super.key, this.booking});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _PayPhase _phase = _PayPhase.idle;

  bool get _busy => _phase != _PayPhase.idle;

  String _label(int total) => switch (_phase) {
        _PayPhase.idle => 'Pay ₹$total',
        _PayPhase.opening => 'Opening…',
        _PayPhase.verifying => 'Verifying…',
      };

  Future<void> _pay(Booking booking) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _phase = _PayPhase.opening);
    try {
      await ref.read(paymentServiceProvider).payForBooking(
            bookingId: booking.id,
            kind: PaymentKind.service,
            description: '${booking.serviceType.label} · ${booking.dateLabel}',
            onVerifying: () {
              if (mounted) setState(() => _phase = _PayPhase.verifying);
            },
          );
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _PayPhase.idle);
      messenger.showSnackBar(_snack(switch (e.type) {
        PaymentErrorType.cancelled => "Payment cancelled — you haven't been charged.",
        PaymentErrorType.failed => "Payment failed — you haven't been charged. Try again.",
        PaymentErrorType.unverified =>
          "Payment couldn't be verified — note payment id ${e.paymentId} and contact support.",
      }));
      return;
    }
    if (mounted) context.go(Routes.bookingConfirmed, extra: booking);
  }

  // Floating with a bottom margin tall enough to clear the fixed Pay/Retry
  // bar docked at the bottom of this screen's body: a default `fixed`
  // SnackBar docks flush to the screen edge and would otherwise sit on top
  // of (and hit-test-block) that button.
  SnackBar _snack(String message) => SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final booking = widget.booking;
    if (booking == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No booking')));
    }
    return PgBackScope(
      // Backing out mid-verification is how a payment succeeds with no
      // booking written. The server owns the paid-write, but the user must
      // not leave before it lands. Only `verifying` is refused: `opening` is
      // the wait for createBookingOrder before Razorpay even opens — nothing
      // has been charged yet, so blocking there only traps the user (no
      // money to protect, and if the Razorpay callback is ever lost the
      // completer never settles, so `_busy` would stay true forever).
      blockWhen: () => _phase == _PayPhase.verifying,
      blockMessage: 'Payment in progress — please wait.',
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(children: [
            Builder(builder: (ctx) =>
              PgAppBar(title: 'Payment', onBack: () => PgBackScope.pop(ctx))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _row(c, 'Professional', booking.proName),
                      _row(c, 'Service', booking.serviceType.label),
                      _row(c, 'When', '${booking.dateLabel} · ${booking.timeSlot}'),
                      _row(c, 'Pet', booking.petName),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Container(height: 1, color: c.border)),
                      _row(c, 'Rate', '₹${booking.rate}'),
                      _row(c, 'Service fee', '₹${booking.fee}'),
                      _row(c, 'Total', '₹${booking.total}', bold: true),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text('🔒 Secured by Razorpay — UPI, cards & netbanking',
                      style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                  color: c.surface, border: Border(top: BorderSide(color: c.border))),
              padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total', style: PgText.inter(12, FontWeight.w400, color: c.faint)),
                  Text('₹${booking.total}', style: PgText.poppins(20, FontWeight.w800, color: c.text)),
                ]),
                const SizedBox(width: 14),
                Expanded(
                    child: GestureDetector(
                        onTap: _busy ? null : () => _pay(booking),
                        child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [c.brand, c.brand2]),
                                borderRadius: BorderRadius.circular(16)),
                            child: Text(_label(booking.total),
                                style: PgText.poppins(15.5, FontWeight.w700,
                                    color: Colors.white))))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(PgColors c, String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: PgText.inter(13, FontWeight.w400, color: c.muted)),
          Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bold
                      ? PgText.poppins(14.5, FontWeight.w800, color: c.text)
                      : PgText.inter(13, FontWeight.w600, color: c.text))),
        ]),
      );
}
