/// How an account proves who it is — decides how sensitive actions (account
/// deletion) re-check the person.
enum AuthMethod { password, google, apple, phone }

class AppUser {
  final String uid;
  final String? email;

  /// Set for accounts that signed in with a phone number. Firebase only
  /// attaches a number after the SMS code was entered, so its presence is
  /// itself proof of ownership.
  final String? phoneNumber;

  /// Whether Firebase has seen this address confirmed via the verification
  /// link. Firebase Auth only ever checks that an address is syntactically
  /// well-formed — it never checks the mailbox exists or that the person
  /// signing up owns it — so this flag is the only real proof of ownership.
  final bool emailVerified;

  /// Whether the account can sign in with a password. False for someone who
  /// only ever used Google, Apple or a phone number — they have no password to
  /// re-enter, so sensitive actions re-check them another way.
  final bool hasPassword;

  final AuthMethod method;

  const AppUser({required this.uid, this.email, this.phoneNumber,
      this.emailVerified = false, this.hasPassword = true, this.method = AuthMethod.password});

  /// The gate for using the app: a confirmed email OR a confirmed phone.
  /// (A phone-only account has no email to verify at all.)
  bool get isVerified => emailVerified || (phoneNumber ?? '').isNotEmpty;
}
