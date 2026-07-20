import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/providers.dart';
import '../../data/services/payment_service.dart';

enum _PayPhase { idle, opening, verifying, saving, retrySave }

class PaymentScreen extends ConsumerStatefulWidget {
  final Booking? draft;
  const PaymentScreen({super.key, this.draft});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _PayPhase _phase = _PayPhase.idle;
  PaymentResult? _paid; // kept across a failed booking write so retry never re-charges

  bool get _busy =>
      _phase == _PayPhase.opening || _phase == _PayPhase.verifying || _phase == _PayPhase.saving;

  String _label(int total) => switch (_phase) {
        _PayPhase.idle => 'Pay ₹$total',
        _PayPhase.opening => 'Opening…',
        _PayPhase.verifying => 'Verifying…',
        _PayPhase.saving => 'Saving…',
        _PayPhase.retrySave => 'Retry saving',
      };

  Future<void> _pay(Booking draft) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_paid == null) {
      setState(() => _phase = _PayPhase.opening);
      try {
        _paid = await ref.read(paymentServiceProvider).payForBooking(
              amountRupees: draft.total,
              description: '${draft.serviceType.label} · ${draft.dateLabel}',
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
      if (!mounted) return;
    }
    setState(() => _phase = _PayPhase.saving);
    final paid = _paid!;
    final booking = Booking(
        parentId: draft.parentId, proId: draft.proId, proName: draft.proName,
        petId: draft.petId, petName: draft.petName, serviceType: draft.serviceType,
        rate: draft.rate, fee: draft.fee, total: draft.total,
        dateLabel: draft.dateLabel, timeSlot: draft.timeSlot, date: draft.date,
        paymentId: paid.paymentId);
    try {
      await ref.read(bookingRepositoryProvider).createBooking(booking);
      if (mounted) context.go(Routes.bookingConfirmed, extra: booking);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _PayPhase.retrySave);
      messenger.showSnackBar(_snack('Payment received (id ${paid.paymentId}) but saving the '
          'booking failed — try again or contact support.'));
    }
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
    final draft = widget.draft;
    if (draft == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No booking')));
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Payment', onBack: () => context.pop()),
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
                    _row(c, 'Professional', draft.proName),
                    _row(c, 'Service', draft.serviceType.label),
                    _row(c, 'When', '${draft.dateLabel} · ${draft.timeSlot}'),
                    _row(c, 'Pet', draft.petName),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(height: 1, color: c.border)),
                    _row(c, 'Rate', '₹${draft.rate}'),
                    _row(c, 'Service fee', '₹${draft.fee}'),
                    _row(c, 'Total', '₹${draft.total}', bold: true),
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
                Text('₹${draft.total}', style: PgText.poppins(20, FontWeight.w800, color: c.text)),
              ]),
              const SizedBox(width: 14),
              Expanded(
                  child: GestureDetector(
                      onTap: _busy ? null : () => _pay(draft),
                      child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.brand, c.brand2]),
                              borderRadius: BorderRadius.circular(16)),
                          child: Text(_label(draft.total),
                              style: PgText.poppins(15.5, FontWeight.w700,
                                  color: Colors.white))))),
            ]),
          ),
        ]),
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
