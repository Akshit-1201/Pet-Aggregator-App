import '../models/app_user.dart';

enum AuthFailureType { invalidCredentials, emailInUse, weakPassword, invalidEmail, network, unknown }

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
}
