import '../models/app_user.dart';

enum AuthFailureType {
  invalidCredentials, emailInUse, weakPassword, invalidEmail, network, unknown,
  /// The email belongs to an account that signs in another way (e.g. a
  /// password account trying Google for the first time).
  accountExistsWithDifferentMethod,
  /// The sign-in provider isn't set up for this build or project yet.
  providerNotConfigured,
}

enum SocialProvider { google, apple }

/// A successful Google/Apple sign-in. [displayName] is what the provider told
/// us (Apple only shares it on the very first sign-in), used to prefill the
/// profile of a brand-new user.
class SocialSignIn {
  final AppUser user;
  final String displayName;
  const SocialSignIn({required this.user, required this.displayName});
}

class AuthFailure implements Exception {
  final AuthFailureType type;
  final String message;
  const AuthFailure(this.type, this.message);

  factory AuthFailure.fromCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return const AuthFailure(AuthFailureType.invalidCredentials, 'Incorrect email or password.');
      case 'email-already-in-use':
        return const AuthFailure(AuthFailureType.emailInUse, 'That email is already registered.');
      case 'weak-password':
        return const AuthFailure(AuthFailureType.weakPassword, 'Password is too weak (min 6 characters).');
      case 'invalid-email':
        return const AuthFailure(AuthFailureType.invalidEmail, 'That email address looks invalid.');
      case 'account-exists-with-different-credential':
        return const AuthFailure(AuthFailureType.accountExistsWithDifferentMethod,
            'This email already has an account. Log in with your password instead.');
      case 'operation-not-allowed':
        return const AuthFailure(AuthFailureType.providerNotConfigured,
            "This sign-in option isn't available yet. Please use email and password.");
      case 'network-request-failed':
        return const AuthFailure(AuthFailureType.network, 'Network error. Check your connection.');
      default:
        return const AuthFailure(AuthFailureType.unknown, 'Something went wrong. Please try again.');
    }
  }

  @override
  String toString() => 'AuthFailure($type): $message';
}

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<AppUser> signUp({required String email, required String password});
  Future<AppUser> signIn({required String email, required String password});
  Future<void> signOut();

  /// Signs in — creating the account on first use — with Google or Apple.
  /// Returns null if the person backed out of the provider's sheet; throws
  /// [AuthFailure] for real failures. The provider has verified the email, so
  /// these accounts skip the confirm-your-email step.
  Future<SocialSignIn?> signInWithProvider(SocialProvider provider);

  /// Which providers this device can offer. Apple is iOS-only here: Android
  /// would need a web redirect flow, and the App Store rule that requires it
  /// (guideline 4.8) applies to iOS.
  List<SocialProvider> get availableProviders;

  /// Emails the account a verification link. Safe to call repeatedly; Firebase
  /// rate-limits on its side.
  Future<void> sendVerificationEmail();

  /// Re-fetches the account from Firebase and returns whether the address is
  /// now verified. Needed because clicking the link happens in a browser —
  /// nothing pushes that back to the app, so the app has to ask.
  Future<bool> refreshEmailVerified();

  /// Proves the person at the keyboard owns the account, by re-checking the
  /// password. Firebase requires a recent sign-in before deletion anyway, and
  /// it stops a borrowed unlocked phone from wiping someone's account.
  /// Throws [AuthFailure] with [AuthFailureType.invalidCredentials] on a wrong
  /// password.
  Future<void> reauthenticate(String password);

  /// [reauthenticate] for an account with no password: re-runs the Google or
  /// Apple sheet for the provider the account uses. Returns false if the
  /// person cancelled.
  Future<bool> reauthenticateWithProvider();

  /// Irreversibly deletes the account and its data. Implemented server-side —
  /// the client cannot reach most of what has to be cleaned up.
  Future<void> deleteAccount();
}
