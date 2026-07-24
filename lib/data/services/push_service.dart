import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Device-token side of push. The Functions decide *what* to send; this decides
/// *where*, by keeping the set of devices a user is signed in on.
///
/// Tokens live in `users/{uid}/fcmTokens/{token}` rather than a field on the
/// user doc, because one account can be on several devices and a field would
/// mean only the most recent one ever gets notified. Tokens also rotate, so the
/// refresh stream has to be handled or notifications quietly stop arriving.
abstract interface class PushService {
  /// Asks the OS for notification permission. Android 13+ requires this at
  /// runtime; earlier versions grant it implicitly.
  Future<bool> requestPermission();

  /// The current device token, or null if permission was refused.
  Future<String?> currentToken();

  /// Fires whenever FCM rotates this device's token.
  Stream<String> onTokenRefresh();

  /// Payloads that arrive while the app is in the foreground — FCM does not
  /// draw a system notification then, so the app surfaces it itself.
  Stream<Map<String, String>> onForegroundMessage();

  /// Payload of the notification the user tapped to open the app, if any.
  /// Covers both a cold start and a resume from background.
  Future<Map<String, String>?> initialTapPayload();
  Stream<Map<String, String>> onNotificationTap();
}

class FirebasePushService implements PushService {
  final FirebaseMessaging _messaging;
  FirebasePushService([FirebaseMessaging? messaging])
      : _messaging = messaging ?? FirebaseMessaging.instance;

  static Map<String, String> _payload(RemoteMessage m) => {
        for (final e in m.data.entries) e.key: '${e.value}',
        if (m.notification?.title != null) 'title': m.notification!.title!,
        if (m.notification?.body != null) 'body': m.notification!.body!,
      };

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> currentToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      // A missing Play Services or a refused permission should degrade to "no
      // push", never take the app down on launch.
      debugPrint('PushService: could not get FCM token: $e');
      return null;
    }
  }

  @override
  Stream<String> onTokenRefresh() => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, String>> onForegroundMessage() =>
      FirebaseMessaging.onMessage.map(_payload);

  @override
  Future<Map<String, String>?> initialTapPayload() async {
    final m = await _messaging.getInitialMessage();
    return m == null ? null : _payload(m);
  }

  @override
  Stream<Map<String, String>> onNotificationTap() =>
      FirebaseMessaging.onMessageOpenedApp.map(_payload);
}
