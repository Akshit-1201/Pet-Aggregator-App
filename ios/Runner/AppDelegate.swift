import Flutter
import GoogleMaps
import UIKit

/// Google Maps SDK for iOS key — the iOS mirror of `com.google.android.geo.API_KEY`
/// in AndroidManifest.xml.
///
/// Committing it is safe ONLY while it is restricted in Cloud Console to iOS
/// apps + bundle id `com.pawgopets.app`. An unrestricted Maps key is billable by
/// anyone who finds it, and this file ships inside the IPA.
///
/// The Android key will NOT work here. Android keys are restricted by package
/// name + SHA-1 fingerprint, a restriction type that does not exist for iOS, so
/// this needs its own key:
///   Cloud Console → enable "Maps SDK for iOS"
///   → APIs & Services → Credentials → Create credentials → API key
///   → Application restrictions: iOS apps → bundle ID com.pawgopets.app
///   → API restrictions: Maps SDK for iOS only
private let googleMapsApiKey = "AIzaSyDv7iqaGP7zIH4-SmlIW7UcjU7vmaw3E5w"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ALWAYS call provideAPIKey, before anything can create a map. The two
    // failure modes are very different:
    //   - a WRONG or unrestricted-mismatch key → blank tiles, app keeps running
    //   - provideAPIKey NEVER CALLED → GMSServices throws an NSException the
    //     moment the first GMSMapView is created, i.e. a hard crash on "See map"
    // An earlier version skipped the call while the key was a placeholder, which
    // turned "blank map" into "app crashes" on every TestFlight build made
    // before the real key landed. Never gate this call again.
    if googleMapsApiKey.hasPrefix("REPLACE_WITH") {
      NSLog("[Pawgo Pets] Google Maps iOS API key is not set — map tiles will render blank. See ios/Runner/AppDelegate.swift.")
    }
    GMSServices.provideAPIKey(googleMapsApiKey)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
