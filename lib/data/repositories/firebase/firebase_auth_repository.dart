import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../firebase_options.dart';
import '../../models/app_user.dart';
import '../auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  FirebaseAuthRepository([FirebaseAuth? auth, FirebaseFunctions? functions])
      : _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  AppUser? _map(User? u) => u == null
      ? null
      : AppUser(
          uid: u.uid, email: u.email, emailVerified: u.emailVerified,
          hasPassword: u.providerData.any((p) => p.providerId == 'password'));

  /// The project's Web OAuth client (client_type 3 in google-services.json).
  /// Android's Credential Manager needs it to mint an ID token Firebase will
  /// accept. A public identifier, not a secret.
  static const _webClientId =
      '280616341211-hhutv7vco4ase5s7qm1vmlk50j449aq4.apps.googleusercontent.com';

  Future<void>? _googleInit;
  Future<void> _ensureGoogle() => _googleInit ??= GoogleSignIn.instance.initialize(
        clientId: !kIsWeb && Platform.isIOS ? DefaultFirebaseOptions.ios.iosClientId : null,
        serverClientId: _webClientId,
      );

  @override
  List<SocialProvider> get availableProviders => [
        SocialProvider.google,
        if (!kIsWeb && Platform.isIOS) SocialProvider.apple,
      ];

  /// The provider's credential, or null if the person cancelled the sheet.
  Future<({AuthCredential credential, String name})?> _providerCredential(
      SocialProvider provider) async {
    switch (provider) {
      case SocialProvider.google:
        await _ensureGoogle();
        final GoogleSignInAccount account;
        try {
          account = await GoogleSignIn.instance.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled ||
              e.code == GoogleSignInExceptionCode.interrupted) {
            return null;
          }
          // clientConfigurationError almost always means the app's SHA-1 isn't
          // registered in Firebase, so there is no Android OAuth client yet.
          debugPrint('Google sign-in failed: ${e.code} ${e.description}');
          throw const AuthFailure(AuthFailureType.providerNotConfigured,
              "Google sign-in isn't available yet. Please use email and password.");
        }
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthFailure(AuthFailureType.unknown, 'Google sign-in failed. Please try again.');
        }
        return (credential: GoogleAuthProvider.credential(idToken: idToken),
            name: account.displayName ?? '');
      case SocialProvider.apple:
        // Firebase checks the Apple ID token was minted for THIS request via
        // the nonce, so a token replayed from elsewhere can't sign anyone in.
        final raw = _nonce();
        final AuthorizationCredentialAppleID apple;
        try {
          apple = await SignInWithApple.getAppleIDCredential(
            scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
            nonce: sha256.convert(utf8.encode(raw)).toString(),
          );
        } on SignInWithAppleAuthorizationException catch (e) {
          if (e.code == AuthorizationErrorCode.canceled) return null;
          debugPrint('Apple sign-in failed: ${e.code} ${e.message}');
          throw const AuthFailure(AuthFailureType.providerNotConfigured,
              "Sign in with Apple isn't available yet. Please use email and password.");
        }
        final name = [apple.givenName, apple.familyName]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');
        return (
          credential: OAuthProvider('apple.com').credential(
              idToken: apple.identityToken, rawNonce: raw, accessToken: apple.authorizationCode),
          name: name,
        );
    }
  }

  static String _nonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  Future<SocialSignIn?> signInWithProvider(SocialProvider provider) async {
    final got = await _providerCredential(provider);
    if (got == null) return null;
    try {
      final cred = await _auth.signInWithCredential(got.credential);
      final user = cred.user!;
      // Apple shares the name only on the very first sign-in; keep it on the
      // account so a reinstall can still prefill the profile.
      if ((user.displayName ?? '').isEmpty && got.name.isNotEmpty) {
        await user.updateDisplayName(got.name).catchError((_) {});
      }
      return SocialSignIn(
          user: _map(_auth.currentUser ?? user)!,
          displayName: got.name.isNotEmpty ? got.name : (user.displayName ?? ''));
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<bool> reauthenticateWithProvider() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final ids = user.providerData.map((p) => p.providerId).toSet();
    final provider = ids.contains('apple.com') ? SocialProvider.apple : SocialProvider.google;
    final got = await _providerCredential(provider);
    if (got == null) return false;
    try {
      await user.reauthenticateWithCredential(got.credential);
      return true;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  Future<AppUser> signUp({required String email, required String password}) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<void> signOut() async {
    // Sign out of Google too, or the next "Continue with Google" silently
    // reuses this account instead of offering the account chooser.
    if (_googleInit != null) {
      await GoogleSignIn.instance.signOut().catchError((_) {});
    }
    await _auth.signOut();
  }

  @override
  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    // Branded HTML email with a real "Verify my email" button, sent by the
    // sendVerificationEmail Function. Firebase's own template prints the raw
    // URL as text (reported as "the link isn't a hyperlink") and its body
    // cannot be edited. The Function answers {sent:false} until Resend is
    // configured, and any failure here falls through to Firebase's email —
    // a user must always get *some* verification link.
    try {
      final res = await _functions.httpsCallable('sendVerificationEmail').call<Object?>();
      final data = res.data;
      if (data is Map && data['sent'] == true) return;
    } catch (_) {
      // Function not deployed yet, offline, etc. — fall back below.
    }
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<bool> refreshEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    // reload() alone is NOT enough. `emailVerified` is read from the cached ID
    // token, which reload() does not refresh — so after clicking the emailed
    // link the flag stayed false until the app was restarted, leaving the user
    // stuck on the "Confirm your email" screen tapping a button that did
    // nothing. Forcing a token refresh is what actually picks the change up.
    // Found on-device; a widget test with a fake repo cannot catch this.
    try {
      await user.getIdToken(true);
    } on FirebaseAuthException {
      // A network blip here just means "not verified yet" — the poll retries.
      return false;
    }
    return _auth.currentUser?.emailVerified ?? false;
  }

  @override
  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthFailure(AuthFailureType.invalidCredentials, 'Please sign in again.');
    }
    try {
      await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password));
    } on FirebaseAuthException catch (e) {
      final f = AuthFailure.fromCode(e.code);
      // fromCode's wording is written for sign-in ("Incorrect email or
      // password"), but re-auth only ever asks for the password — the email is
      // the one already signed in, so it cannot be the wrong half.
      if (f.type == AuthFailureType.invalidCredentials) {
        throw const AuthFailure(AuthFailureType.invalidCredentials, 'Incorrect password.');
      }
      throw f;
    }
  }

  @override
  Future<void> deleteAccount() async {
    // The Function does the fan-out delete AND removes the auth user, so there
    // is no client-side _auth.currentUser.delete() here — calling both would
    // race, and the second would fail on an already-deleted account.
    await _functions.httpsCallable('deleteMyAccount').call<Map<String, dynamic>>();
    await _auth.signOut();
  }
}
