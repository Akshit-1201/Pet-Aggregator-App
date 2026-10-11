class AppUser {
  final String uid;
  final String? email;

  /// Whether Firebase has seen this address confirmed via the verification
  /// link. Firebase Auth only ever checks that an address is syntactically
  /// well-formed — it never checks the mailbox exists or that the person
  /// signing up owns it — so this flag is the only real proof of ownership.
  final bool emailVerified;

  /// Whether the account can sign in with a password. False for someone who
  /// only ever used Google or Apple — they have no password to re-enter, so
  /// sensitive actions (account deletion) re-check them with the provider.
  final bool hasPassword;

  const AppUser({required this.uid, this.email, this.emailVerified = false,
      this.hasPassword = true});
}
