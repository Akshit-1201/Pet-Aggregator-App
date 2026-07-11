import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/providers.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final Booking? draft;
  const PaymentScreen({super.key, this.draft});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _paying = false;

  Future<void> _pay(Booking draft) async {
    setState(() => _paying = true);
    await ref.read(bookingRepositoryProvider).createBooking(draft);
    if (mounted) context.go(Routes.bookingConfirmed, extra: draft);
  }

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
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF2C241E), Color(0xFF5A3D2C)]),
                    borderRadius: BorderRadius.circular(20), boxShadow: c.shadow),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('PAWGO PAY', style: PgText.inter(12, FontWeight.w500,
                        color: Colors.white).copyWith(letterSpacing: 1)),
                      Text('VISA', style: PgText.poppins(15, FontWeight.w800, color: Colors.white)),
                    ]),
                    const SizedBox(height: 24),
                    Text('•••• •••• •••• 4421', style: PgText.poppins(19, FontWeight.w600,
                      color: Colors.white).copyWith(letterSpacing: 2)),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Card on file', style: PgText.inter(12, FontWeight.w400, color: Colors.white70)),
                      Text('09/28', style: PgText.inter(12, FontWeight.w400, color: Colors.white70)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 18),
                Text('Other options', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                _option('📱', 'UPI', 'GPay · PhonePe · Paytm', c),
                const SizedBox(height: 11),
                _option('💵', 'Pawgo Wallet', 'Balance ₹1,540', c),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total', style: PgText.inter(12, FontWeight.w400, color: c.faint)),
                Text('₹${draft.total}', style: PgText.poppins(20, FontWeight.w800, color: c.text)),
              ]),
              const SizedBox(width: 14),
              Expanded(child: GestureDetector(
                onTap: _paying ? null : () => _pay(draft),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]),
                    borderRadius: BorderRadius.circular(16)),
                  child: Text(_paying ? 'Paying…' : 'Pay ₹${draft.total}',
                    style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _option(String emoji, String title, String sub, PgColors c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(15)),
        child: Row(children: [
          Container(width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11)),
            child: Text(emoji, style: const TextStyle(fontSize: 17))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.inter(14, FontWeight.w700, color: c.text)),
            Text(sub, style: PgText.inter(12, FontWeight.w400, color: c.muted)),
          ])),
          Container(width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.border, width: 2))),
        ]),
      );
}
