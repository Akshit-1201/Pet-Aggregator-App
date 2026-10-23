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

/// An SMS code is on its way to [phoneNumber]; pass this back with the code.
/// [autoVerified] means Android read the SMS itself and the account is
/// already signed in — there is nothing for the person to type.
class PhoneVerification {
  final String verificationId, phoneNumber;
  final int? resendToken;
  final bool autoVerified;
  const PhoneVerification({required this.verificationId, required this.phoneNumber,
      this.resendToken, this.autoVerified = false});
}

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
      case 'invalid-phone-number':
        return const AuthFailure(AuthFailureType.invalidEmail, "That phone number doesn't look right.");
      case 'invalid-verification-code':
        return const AuthFailure(AuthFailureType.invalidCredentials, "That code isn't right. Check the SMS and try again.");
      case 'session-expired':
      case 'code-expired':
        return const AuthFailure(AuthFailureType.invalidCredentials, 'That code has expired. Send a new one.');
      case 'too-many-requests':
      case 'quota-exceeded':
        return const AuthFailure(AuthFailureType.network, 'Too many attempts. Please wait a while and try again.');
      case 'missing-client-identifier':
      case 'app-not-authorized':
        return const AuthFailure(AuthFailureType.providerNotConfigured,
            "Phone sign-in isn't available yet. Please use email instead.");
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

  /// Texts a one-time code to [phoneE164] (e.g. +919812345678) to sign in —
  /// creating the account on first use. Pass the previous [resendToken] to
  /// resend. Throws [AuthFailure].
  Future<PhoneVerification> sendPhoneCode(String phoneE164, {int? resendToken});

  /// Signs in with the code from the SMS. A phone account has no email or
  /// password; the confirmed number is what verifies it.
  Future<SocialSignIn> confirmPhoneCode(PhoneVerification v, String code);

  /// Account deletion for a phone account: texts a code to its own number…
  Future<PhoneVerification> sendReauthPhoneCode();

  /// …and checks it. Throws [AuthFailure] on a wrong or expired code.
  Future<void> confirmReauthPhoneCode(PhoneVerification v, String code);

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
