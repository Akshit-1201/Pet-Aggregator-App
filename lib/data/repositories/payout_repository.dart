import '../models/payout_account.dart';

/// Errors [PayoutRepository.createAccount] can surface, mapped from the
/// Function's error codes so the UI can say something specific rather than
/// "something went wrong".
enum PayoutFailureType {
  panInvalid,
  ifscInvalid,
  accountNumberInvalid,
  emailInvalid,
  nameRequired,
  alreadyExists,
  unknown,
}

class PayoutFailure implements Exception {
  final PayoutFailureType type;
  final String message;
  const PayoutFailure(this.type, this.message);

  factory PayoutFailure.fromCode(String code) => switch (code) {
        'pan-invalid' => const PayoutFailure(
            PayoutFailureType.panInvalid, 'That PAN doesn\'t look right (e.g. ABCDE1234F).'),
        'ifsc-invalid' => const PayoutFailure(
            PayoutFailureType.ifscInvalid, 'That IFSC doesn\'t look right (e.g. HDFC0001234).'),
        'account-number-invalid' => const PayoutFailure(PayoutFailureType.accountNumberInvalid,
            'Enter your account number using digits only.'),
        'email-invalid' =>
          const PayoutFailure(PayoutFailureType.emailInvalid, 'Enter a valid email address.'),
        'name-required' || 'beneficiary-name-required' => const PayoutFailure(
            PayoutFailureType.nameRequired, 'Enter the name on the bank account.'),
        'payout-account-exists' => const PayoutFailure(PayoutFailureType.alreadyExists,
            'Payout details are already set up. Contact support to change them.'),
        _ => const PayoutFailure(
            PayoutFailureType.unknown, "Couldn't save those details. Please try again."),
      };

  @override
  String toString() => 'PayoutFailure($type): $message';
}

abstract interface class PayoutRepository {
  /// The partner's own payout account, or null if they haven't set one up.
  Stream<PayoutAccount?> watchMyAccount(String uid);

  /// Everything they've earned.
  Stream<List<Payout>> watchMyPayouts(String uid);

  /// Sends bank details to the server, which registers them with Razorpay.
  ///
  /// The details are **not** persisted by Pawgo — they pass through the
  /// Function to Razorpay and only an account id and masked last-4 come back.
  Future<void> createAccount({
    required String name,
    required String email,
    required String pan,
    required String accountNumber,
    required String ifsc,
    required String beneficiaryName,
  });
}
