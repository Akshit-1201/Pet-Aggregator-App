enum PayoutAccountStatus {
  pending('pending'),
  active('active'),
  failed('failed');

  final String storageKey;
  const PayoutAccountStatus(this.storageKey);

  static PayoutAccountStatus fromStorage(String key) => PayoutAccountStatus.values
      .firstWhere((s) => s.storageKey == key, orElse: () => PayoutAccountStatus.pending);
}

/// What Pawgo keeps about a partner's bank account — deliberately almost
/// nothing.
///
/// The account number and PAN are sent straight to Razorpay by the
/// `createPayoutAccount` Function and are **never written to Firestore**.
/// Razorpay is the system of record; the partner never needs to read them back,
/// so storing them would add risk for no product benefit. [bankLast4] exists
/// only so someone can recognise which account they gave us.
class PayoutAccount {
  final String uid, razorpayAccountId, bankLast4, ifsc, beneficiaryName, error;
  final PayoutAccountStatus status;

  const PayoutAccount({
    required this.uid,
    required this.razorpayAccountId,
    required this.bankLast4,
    required this.ifsc,
    required this.beneficiaryName,
    this.status = PayoutAccountStatus.pending,
    this.error = '',
  });

  factory PayoutAccount.fromMap(String uid, Map<String, dynamic> m) => PayoutAccount(
        uid: uid,
        razorpayAccountId: (m['razorpayAccountId'] ?? '') as String,
        bankLast4: (m['bankLast4'] ?? '') as String,
        ifsc: (m['ifsc'] ?? '') as String,
        beneficiaryName: (m['beneficiaryName'] ?? '') as String,
        status: PayoutAccountStatus.fromStorage((m['status'] ?? 'pending') as String),
        error: (m['error'] ?? '') as String,
      );
}

enum PayoutStatus {
  owed('owed', 'Owed'),
  held('held', 'Processing'),
  released('released', 'Paid out'),
  reversed('reversed', 'Cancelled'),
  failed('failed', 'Failed');

  final String storageKey, label;
  const PayoutStatus(this.storageKey, this.label);

  static PayoutStatus fromStorage(String key) => PayoutStatus.values
      .firstWhere((s) => s.storageKey == key, orElse: () => PayoutStatus.owed);
}

/// One booking's worth of earnings. Written by the server when a customer pays;
/// clients only ever read their own.
class Payout {
  final String id, kind, bookingId, partnerId;
  final int amount, dueAt, createdAt;
  final PayoutStatus status;

  const Payout({
    required this.id,
    required this.kind,
    required this.bookingId,
    required this.partnerId,
    required this.amount,
    required this.status,
    this.dueAt = 0,
    this.createdAt = 0,
  });

  factory Payout.fromMap(String id, Map<String, dynamic> m) => Payout(
        id: id,
        kind: (m['kind'] ?? '') as String,
        bookingId: (m['bookingId'] ?? '') as String,
        partnerId: (m['partnerId'] ?? '') as String,
        amount: (m['amount'] ?? 0) as int,
        status: PayoutStatus.fromStorage((m['status'] ?? 'owed') as String),
        dueAt: (m['dueAt'] ?? 0) as int,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}

/// Totals a partner sees. `pending` covers everything not yet paid out —
/// reversed payouts are excluded because that money went back to the customer.
class EarningsSummary {
  final int pending, paid;
  const EarningsSummary({this.pending = 0, this.paid = 0});

  factory EarningsSummary.from(List<Payout> payouts) {
    var pending = 0;
    var paid = 0;
    for (final p in payouts) {
      switch (p.status) {
        case PayoutStatus.owed:
        case PayoutStatus.held:
          pending += p.amount;
        case PayoutStatus.released:
          paid += p.amount;
        case PayoutStatus.reversed:
        case PayoutStatus.failed:
          break;
      }
    }
    return EarningsSummary(pending: pending, paid: paid);
  }
}
