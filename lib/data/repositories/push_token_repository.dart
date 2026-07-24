/// Stores which devices a user should be notified on.
///
/// Keyed by the token itself under `users/{uid}/fcmTokens/{token}`, so signing
/// in on a second device adds rather than replaces — a field on the user doc
/// would silently mean only the newest device ever gets a notification.
abstract interface class PushTokenRepository {
  Future<void> saveToken(String uid, String token);

  /// Called on sign-out so a shared or resold device stops receiving the
  /// previous user's notifications.
  Future<void> removeToken(String uid, String token);
}
