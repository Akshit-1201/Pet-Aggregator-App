// Payouts. The two properties worth pinning: Pawgo never holds a bank account
// number, and the earnings total must not count money that went back to a
// customer.
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/payout_account.dart';
import 'package:pet_aggregator_app/data/repositories/payout_repository.dart';
import '../support/fakes.dart';

Payout _p(String id, int amount, PayoutStatus status) =>
    Payout(id: id, kind: 'service', bookingId: id, partnerId: 'pro1',
        amount: amount, status: status);

void main() {
  test('earnings count owed and held as pending, released as paid', () {
    final summary = EarningsSummary.from([
      _p('a', 250, PayoutStatus.owed),
      _p('b', 300, PayoutStatus.held),
      _p('c', 400, PayoutStatus.released),
    ]);
    expect(summary.pending, 550);
    expect(summary.paid, 400);
  });

  test('a reversed payout counts as neither', () {
    // The stay was cancelled and the guest refunded — that money is not the
    // host's, pending or otherwise.
    final summary = EarningsSummary.from([
      _p('a', 900, PayoutStatus.reversed),
      _p('b', 250, PayoutStatus.owed),
    ]);
    expect(summary.pending, 250);
    expect(summary.paid, 0);
  });

  test('a failed payout is not silently counted as paid', () {
    final summary = EarningsSummary.from([_p('a', 250, PayoutStatus.failed)]);
    expect(summary.paid, 0);
    expect(summary.pending, 0);
  });

  test('only a masked last-4 comes back from account creation', () async {
    final repo = InMemoryPayoutRepository();
    await repo.createAccount(
      name: 'Aarav Sharma', email: 'a@x.com', pan: 'ABCDE1234F',
      accountNumber: '00123456789', ifsc: 'HDFC0001234',
      beneficiaryName: 'Aarav Sharma');

    final account = repo.accounts['uid_me@x.com']!;
    expect(account.bankLast4, '6789');
    // The model has nowhere to put a full account number or a PAN, by design —
    // they go straight to Razorpay and are never persisted by Pawgo.
    expect(account.razorpayAccountId, isNotEmpty);
  });

  test('server error codes map to something a partner can act on', () {
    expect(PayoutFailure.fromCode('pan-invalid').type, PayoutFailureType.panInvalid);
    expect(PayoutFailure.fromCode('ifsc-invalid').message, contains('IFSC'));
    expect(PayoutFailure.fromCode('payout-account-exists').type,
        PayoutFailureType.alreadyExists);
    // Anything unrecognised must still be a usable message, not a raw code.
    expect(PayoutFailure.fromCode('some-new-code').type, PayoutFailureType.unknown);
    expect(PayoutFailure.fromCode('some-new-code').message, isNotEmpty);
  });
}
