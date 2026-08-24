import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'data/repositories/providers.dart';
import 'data/repositories/local/shared_preferences_repository.dart';

/// Attests that requests come from the genuine, unmodified Pawgo app on a
/// genuine device. This is **not** authentication — Firebase Auth answers "who
/// are you", App Check answers "is this really the app". Without it, a stolen
/// ID token replayed from a script passes every check the backend has.
///
/// Must run after `Firebase.initializeApp` and before any Firebase call, so the
/// SDKs attach a token to their very first request.
///
/// **Debug builds use the debug provider**, which prints a token to logcat on
/// first run. That token has to be registered in Firebase Console → App Check →
/// Manage debug tokens, once per machine/emulator, or the build is rejected the
/// moment enforcement is switched on. Release builds use Play Integrity, which
/// requires the app to be distributed through Play; the iOS equivalent is App
/// Attest, which needs the App Attest capability enabled on the App ID.
Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      // `providerAndroid`, not the deprecated `androidProvider` enum.
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      // iOS: App Attest where the OS supports it, DeviceCheck on older devices.
      // Not optional to state -- the plugin defaults to plain DeviceCheck for
      // BOTH modes, and DeviceCheck cannot attest on the simulator, so a debug
      // run would start failing the moment enforcement is switched on.
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    // A device without Play Services, or a misconfigured project, must not stop
    // the app from launching. With enforcement off this is harmless; with it on
    // the backend rejects the requests anyway, which is the correct outcome —
    // but crashing on startup never is.
    debugPrint('App Check activation failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [preferencesRepositoryProvider.overrideWithValue(SharedPreferencesRepository(prefs))],
    child: const PawgoApp(),
  ));
}
