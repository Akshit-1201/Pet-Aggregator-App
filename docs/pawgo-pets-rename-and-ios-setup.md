# Pawgo Pets — rename + iOS/TestFlight setup

The app was renamed to **Pawgo Pets** with the ID **`com.pawgopets.app`** on both
platforms (was `com.pawgo.app`). This was done before any store publication, so
nothing was orphaned — but it invalidates every registration bound to the old ID.

**The Android build is broken until Step 1 is done.** That is expected:

```
Execution failed for task ':app:processDebugGoogleServices'.
> No matching client found for package name 'com.pawgopets.app'
```

`android/app/google-services.json` still describes `com.pawgo.app`. Step 1 fixes
both platforms at once.

---

## Already done in the repo

| File | Change |
|---|---|
| `android/app/build.gradle.kts` | `namespace` + `applicationId` → `com.pawgopets.app` |
| `android/app/src/main/AndroidManifest.xml` | `android:label` → `Pawgo Pets`; Maps-key comment flags the stale restriction |
| `android/app/src/main/kotlin/com/pawgopets/app/MainActivity.kt` | moved from `com/pawgo/app/`, `package` updated |
| `ios/Runner.xcodeproj/project.pbxproj` | all 6 `PRODUCT_BUNDLE_IDENTIFIER` entries; deployment target 13.0 → **15.0** |
| `ios/Runner/Info.plist` | `CFBundleDisplayName` + `CFBundleName` → `Pawgo Pets` |
| `ios/Runner/AppDelegate.swift` | `GMSServices.provideAPIKey` wiring + placeholder key |
| `lib/app.dart`, `lib/features/onboarding/splash_screen.dart`, `lib/data/services/razorpay_payment_service.dart` | in-app wordmark, `MaterialApp` title, Razorpay checkout name → `Pawgo Pets` |
| `test/features/splash_screen_test.dart` | asserts the new wordmark |

`flutter analyze` clean, `flutter test` 443 passing.

The deployment-target bump is required, not cosmetic: `firebase_core` 4.x pulls
Firebase iOS SDK 12, whose floor is iOS 15. CocoaPods refuses to resolve at 13.0.

**Not affected by the rename:** the release keystore. Keystores are not bound to
a package name — `pawgo-release.jks` and `key.properties` carry over untouched.

---

## Step 1 — Re-register both apps with Firebase ← *do this first*

One command does Android and iOS together, rewrites `lib/firebase_options.dart`,
and drops both native config files in place. Run it **on the Mac**, from the repo
root:

```bash
dart pub global activate flutterfire_cli
flutterfire configure \
  --project=pet-aggregator-app \
  --platforms=android,ios \
  --android-package-name=com.pawgopets.app \
  --ios-bundle-id=com.pawgopets.app
```

It offers to register apps that don't exist yet — say yes for both. Afterwards:

- `android/app/google-services.json` describes `com.pawgopets.app` → Android builds again
- `ios/Runner/GoogleService-Info.plist` exists for the first time
- `lib/firebase_options.dart` iOS block no longer says `com.example.petAggregatorApp`

Both config files are public client config, same class as the committed
`google-services.json`. Commit them.

**Verify the plist is in the Xcode target**, not just on disk — open
`ios/Runner.xcworkspace`, select `GoogleService-Info.plist`, and confirm **Runner**
is ticked under Target Membership. A plist that isn't in the target isn't in the
bundle, and Firebase fails at launch with an unhelpful error.

The old `com.example.petAggregatorApp` iOS app and the `com.pawgo.app` Android app
can be deleted in Firebase Console once this works.

## Step 2 — Maps keys

Two separate jobs; the Android key does **not** work on iOS. Android keys are
restricted by package name + SHA-1, a restriction type iOS keys don't have.

**2a. Fix the existing Android key.** Cloud Console → APIs & Services →
Credentials → **"Pawgo Android Maps"** → Application restrictions → change the
allowed package from `com.pawgo.app` to `com.pawgopets.app`, keeping both SHA-1
fingerprints. Until this is done the Android map renders blank tiles.

While you're there, add the **Mac's debug SHA-1** as a third entry — the debug
keystore is per-machine, so the Mac's differs from the Windows one:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android | grep SHA1
```

**2b. Create the iOS key.** Cloud Console → enable **Maps SDK for iOS** →
Credentials → Create credentials → API key →
- Application restrictions: **iOS apps** → bundle ID `com.pawgopets.app`
- API restrictions: **Maps SDK for iOS** only

Paste it into `ios/Runner/AppDelegate.swift`, replacing
`REPLACE_WITH_IOS_MAPS_API_KEY`. Committing it is safe *only because* of the
bundle-ID restriction — an unrestricted Maps key is billable by anyone who finds
it, and this file ships inside the IPA.

Until it's replaced, the app logs on launch:

```
[Pawgo Pets] Google Maps iOS API key is not set — map tiles will render blank.
```

## Step 3 — Push notifications (APNs)

Without this, `firebase_messaging` silently never delivers on iOS.

1. Apple Developer → **Certificates, Identifiers & Profiles → Keys** → new key,
   enable **Apple Push Notifications service (APNs)**. Downloads a `.p8`.
   **It can be downloaded exactly once** — back it up like the keystore.
2. Firebase Console → Project settings → **Cloud Messaging** → Apple app
   configuration → upload the `.p8` with its **Key ID** and your **Team ID**.
3. Xcode → Runner target → **Signing & Capabilities** → add **Push Notifications**
   and **Background Modes → Remote notifications**. This creates
   `ios/Runner/Runner.entitlements`, which doesn't exist yet — let Xcode generate
   it rather than hand-writing it.

The `.p8` lives in Firebase and your backups. Never in the repo.

## Step 4 — Signing

`CODE_SIGN_STYLE = Automatic` is already set, so this is mostly clicking.

1. Xcode → Settings → Accounts → add your Apple ID (needs an active **Apple
   Developer Program** membership — TestFlight requires it).
2. Open `ios/Runner.xcworkspace` → Runner target → Signing & Capabilities →
   select your **Team**. Xcode writes `DEVELOPMENT_TEAM` into the pbxproj and
   creates the certificate + provisioning profile in your Keychain.
3. App Store Connect → create the app record with bundle ID `com.pawgopets.app`.

Certificates and profiles live in the Mac's Keychain, never in the repo.

## Step 5 — App Check (optional now, required later)

`lib/main.dart` uses `AppleAppAttestWithDeviceCheckFallbackProvider` in release.
Add the **App Attest** capability to the App ID and register the iOS app under
Firebase → App Check. Enforcement is still `false` in `functions/src/index.ts`, so
this will not block TestFlight — but debug builds print a token to register, same
as Android.

## Step 6 — Build and upload

```bash
flutter clean
flutter pub get
flutter build ipa --release
```

The Podfile doesn't exist yet; Flutter generates it and runs `pod install` on the
first iOS build. CocoaPods must be installed (`sudo gem install cocoapods`).

Then open `build/ios/archive/Runner.xcarchive` in Xcode → **Distribute App → App
Store Connect → Upload**, or use Transporter.

---

## Razorpay — nothing to do

Already covered and unchanged by any of this. The key ID reaches the client at
runtime from `createBookingOrder`; the key secret never leaves the server. Test
keys are live in Secret Manager and the five payment functions are deployed.
`razorpay_flutter` needs no iOS credential.

Do give the payment flow a real pass on an iOS device — the checkout is a native
sheet and behaves differently from Android. Test card (the generic
`4111 1111 1111 1111` is rejected on this India account): **5267 3181 8797 5449**,
expiry `12/30`, any CVV, OTP `1111`.

---

## Verify

```bash
flutter analyze                 # clean
flutter test                    # 443 passing
flutter build apk --debug       # proves Step 1 landed
flutter build ipa --release     # proves Steps 1-4 landed
```

## Still open

- **The whole app has never had an iOS QA pass.** `CLAUDE.md` describes it as
  Android-only. Permission prompts, the back gesture, keyboard insets, the
  Razorpay sheet and the maps screens all need checking on a real device.
- The **"Pawgo Verified"** badge text (`host_profile_screen`, `verified_badge`)
  was left as-is — it reads as a trust-mark rather than the app name. Rename it
  to "Pawgo Pets Verified" only if that's the intent.
- `web/` and `macos/` still carry the old `pet_aggregator_app` scaffold names.
  Neither is a shipping target, so they were left alone.
