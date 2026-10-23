# Plan — production on `pawgo-pets`, dev on `pet-aggregator-app`

> **Status: documentation only — nothing implemented yet.** This describes the
> process; no code, config or console change has been made for it.
> (A trial start on 2026-10-24 was fully reverted. Leftover: an empty
> "Pawgo Pets Dev" Android app registration in `pet-aggregator-app` with no
> fingerprints — remove it in Project settings → Your apps, or reuse it in
> Phase A step 1.)

Spec: `docs/superpowers/specs/2026-10-24-pawgo-firebase-client-project-design.md`.
👤 = owner/client console step · 💻 = Claude (code/CLI) · ✅ verify.

## Phase A — dev side (no client access needed)

1. 💻 Register Android app `com.pawgopets.app.dev` ("Pawgo Pets Dev") in
   `pet-aggregator-app`; add the Windows debug + release SHA-1/SHA-256; fetch
   its `google-services.json` → `android/app/src/dev/`.
2. 💻 Android flavors `dev`/`prod` in `build.gradle.kts` (dev:
   `applicationIdSuffix ".dev"`, app name "Pawgo Pets Dev"); Maps key via
   `manifestPlaceholders`.
3. 💻 `lib/core/env/app_env.dart` + `firebase_options_dev.dart`; `main.dart`
   and the Google web client ID read from it. Unit test: `dev` flavor → dev
   project; null/`prod` → prod.
4. 💻 `firestore.rules` bucket check accepts either project; `.firebaserc`
   aliases; admin client config env-driven.
5. 👤 "Pawgo Android Maps" key in `pet-aggregator-app`: add
   `com.pawgopets.app.dev` + debug and release SHA-1.
6. ✅ `flutter analyze`, `flutter test`, `flutter build apk --debug --flavor dev`,
   run dev on the emulator against `pet-aggregator-app`.

## Phase B — client project prerequisites (👤, in this order)

1. Client: IAM → add `akshitnegi2010@gmail.com` as **Owner** on `pawgo-pets`.
2. Client: Billing → link a **Blaze** billing account (Functions, Storage,
   Vision need it). Set a budget alert.
3. Firestore → Create database → **Native**, location **asia-south1 (Mumbai)**,
   start in production mode (our rules get deployed over it).
4. Storage → Get started → location **asia-south1**.
5. Authentication → Get started → enable **Email/Password, Google, Apple,
   Phone**; Settings → **SMS region policy: India only**; Phone → test number
   `+91 99999 00001` / `123456`.
6. Cloud Console (project `pawgo-pets`) → enable **Cloud Vision API**, **Play
   Integrity API**, **Maps SDK for Android**, **Maps SDK for iOS**.

## Phase C — wire production (💻 once access exists)

1. Free the package: remove `com.pawgopets.app`'s SHA fingerprints from
   `pet-aggregator-app` (its Android OAuth clients go with them).
2. Register in `pawgo-pets`: Android `com.pawgopets.app` (+ release and debug
   SHA-1/SHA-256), iOS `com.pawgopets.app`, Web app "Pawgo Admin".
3. Generate `firebase_options_prod.dart`, `android/app/src/prod/google-services.json`,
   `ios/Runner/GoogleService-Info.plist`; update `Info.plist` URL schemes and
   the prod web client ID.
4. 👤 Maps keys in `pawgo-pets`: Android key restricted to `com.pawgopets.app` +
   release SHA-1 (+ debug); iOS key restricted to bundle `com.pawgopets.app` →
   💻 wire both.
5. 👤 Secrets in `pawgo-pets`: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` (test
   keys for now), `RESEND_API_KEY` = `unset` (deploy refuses without a value).
6. 👤 Deploy: `firebase deploy --project prod --only firestore,storage,functions`.
   If an event trigger fails with an Eventarc permission error on the first
   deploy, retry after a few minutes (seen before on this codebase).
7. 👤 Admin panel: new service-account key from `pawgo-pets` → `admin/.env.local`;
   `node admin/scripts/bootstrap-admin.mjs <email>`.
8. 👤 App Check: register Android (Play Integrity, release SHA-256) and iOS
   (App Attest) in `pawgo-pets` (enforcement stays off until after release).
9. 👤 iOS push: upload the APNs `.p8` to `pawgo-pets` Cloud Messaging.

## Phase D — verify

- ✅ Release `--flavor prod` on the emulator: phone sign-in (test number) →
  setup → Home; map tiles; photo upload (Vision); a test-mode Razorpay booking
  → confirmed (server pricing, Functions in the new project); delete account.
- ✅ Dev flavor still works against `pet-aggregator-app`, installed alongside.
- ✅ Update `CLAUDE.md` (flavors, which project is which, deploy aliases),
  `docs/launch-checklist.md`, `docs/client-feedback-2026-10-setup.md`.
