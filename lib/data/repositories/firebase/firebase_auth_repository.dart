import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      : AppUser(uid: u.uid, email: u.email, emailVerified: u.emailVerified);

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
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
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
      throw AuthFailure.fromCode(e.code);
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
