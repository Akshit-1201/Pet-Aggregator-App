import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/payout_account.dart';
import '../../data/repositories/payout_repository.dart';
import '../../data/repositories/providers.dart';

/// Earnings + bank details, embedded in Pro-setup and Host-setup.
///
/// Payout details are **optional**: a partner lists and takes bookings straight
/// away and their earnings accrue as "owed". Being owed money is the strongest
/// prompt there is to finish this, and demanding a PAN before anyone has earned
/// a rupee would choke off supply.
class EarningsCard extends ConsumerStatefulWidget {
  const EarningsCard({super.key});

  @override
  ConsumerState<EarningsCard> createState() => _EarningsCardState();
}

class _EarningsCardState extends ConsumerState<EarningsCard> {
  final _beneficiary = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _pan = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _beneficiary.dispose();
    _account.dispose();
    _ifsc.dispose();
    _pan.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
      await ref.read(payoutRepositoryProvider).createAccount(
            name: profile?.name ?? _beneficiary.text.trim(),
            email: profile?.email ?? '',
            pan: _pan.text.trim(),
            accountNumber: _account.text.trim(),
            ifsc: _ifsc.text.trim(),
            beneficiaryName: _beneficiary.text.trim(),
          );
      if (mounted) {
        // Cleared immediately — these never need to be held in memory again,
        // and Pawgo does not store them anywhere.
        _account.clear();
        _pan.clear();
        setState(() => _open = false);
        showPgSnack(context, 'Bank details sent. Verification usually takes a day or two.');
      }
    } on PayoutFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't save those details. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final account = ref.watch(myPayoutAccountProvider).value;
    final earnings = ref.watch(myEarningsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Earnings & payouts',
                  style: PgText.poppins(16, FontWeight.w800, color: c.text))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _stat(c, '₹${earnings.pending}', 'Pending')),
          Container(width: 1, height: 34, color: c.border),
          Expanded(child: _stat(c, '₹${earnings.paid}', 'Paid out')),
        ]),
        const SizedBox(height: 14),
        ..._accountSection(c, account),
      ]),
    );
  }

  List<Widget> _accountSection(PgColors c, PayoutAccount? account) {
    if (account != null) {
      return [
        Text(
            account.status == PayoutAccountStatus.active
                ? 'Paying out to ••••${account.bankLast4} (${account.ifsc}).'
                : 'Bank account ••••${account.bankLast4} is being verified. '
                    'Earnings keep accruing meanwhile.',
            style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
        const SizedBox(height: 6),
        Text('Money is released after each booking is complete.',
            style: PgText.inter(12, FontWeight.w400, color: c.faint)),
      ];
    }

    if (!_open) {
      return [
        Text('Add a bank account to get paid. Your earnings are safe until you do.',
            style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _open = true),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.brand, c.brand2]),
                borderRadius: BorderRadius.circular(14)),
            child: Text('Add bank details',
                style: PgText.poppins(14.5, FontWeight.w700, color: Colors.white))),
        ),
      ];
    }

    return [
      PgTextField(label: 'Name on the account', controller: _beneficiary, hint: 'Aarav Sharma'),
      const SizedBox(height: 12),
      PgTextField(
          label: 'Account number',
          controller: _account,
          keyboardType: TextInputType.number,
          hint: '00123456789'),
      const SizedBox(height: 12),
      PgTextField(label: 'IFSC', controller: _ifsc, hint: 'HDFC0001234'),
      const SizedBox(height: 12),
      PgTextField(label: 'PAN', controller: _pan, hint: 'ABCDE1234F'),
      const SizedBox(height: 8),
      Text('Sent straight to our payments provider — Pawgo never stores your '
          'account number or PAN.',
          style: PgText.inter(12, FontWeight.w400, color: c.faint, height: 1.4)),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart)),
      ],
      const SizedBox(height: 12),
      GestureDetector(
        onTap: _busy ? null : _submit,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.brand, c.brand2]),
              borderRadius: BorderRadius.circular(14)),
          child: Text(_busy ? 'Saving…' : 'Save bank details',
              style: PgText.poppins(14.5, FontWeight.w700, color: Colors.white))),
      ),
    ];
  }

  Widget _stat(PgColors c, String value, String label) => Column(children: [
        Text(value, style: PgText.poppins(18, FontWeight.w800, color: c.text)),
        Text(label, style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]);
}
