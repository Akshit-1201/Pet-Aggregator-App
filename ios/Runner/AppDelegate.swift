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
private let googleMapsApiKey = "REPLACE_WITH_IOS_MAPS_API_KEY"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A missing or wrong key makes the SDK render blank tiles with no error
    // anywhere, which is a miserable thing to debug. Say so in the log instead.
    if googleMapsApiKey.hasPrefix("REPLACE_WITH") {
      NSLog("[Pawgo Pets] Google Maps iOS API key is not set — map tiles will render blank. See ios/Runner/AppDelegate.swift.")
    } else {
      GMSServices.provideAPIKey(googleMapsApiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
