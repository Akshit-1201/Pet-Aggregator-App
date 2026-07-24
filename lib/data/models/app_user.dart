class AppUser {
  final String uid;
  final String? email;

  /// Whether Firebase has seen this address confirmed via the verification
  /// link. Firebase Auth only ever checks that an address is syntactically
  /// well-formed — it never checks the mailbox exists or that the person
  /// signing up owns it — so this flag is the only real proof of ownership.
  final bool emailVerified;

  const AppUser({required this.uid, this.email, this.emailVerified = false});
}
