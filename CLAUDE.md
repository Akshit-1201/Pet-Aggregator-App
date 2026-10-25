# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Pawgo Pets** — a Flutter + Firebase "pet aggregator" app (Android + iOS, Mumbai market). It bundles four products behind one account: Discovery/Matching ("Woof"), a Services marketplace, Homestay boarding, and a Community forum.

The entire UI already exists as a 30-screen prototype the owner designed in claude.ai/design. **We are porting that prototype into Flutter, not designing from scratch.** The prototype is the source of truth for every colour, font, radius and layout:

- `Design/Pawgo Prototype.dc.html` — the full prototype (note the capital D — it matters on macOS/Linux) (self-contained HTML; open in a browser to see the target). Design tokens live in its top `<style>` block (`--brand:#F59E2E`, cream `--bg:#FBF1E8`, Poppins + Inter, full light **and** dark themes).

## Working method (important)

This repo is built with the Superpowers spec → plan → execute workflow. Before implementing a feature, read its spec and plan:

- Specs: `docs/superpowers/specs/`
- Plans: `docs/superpowers/plans/` (bite-sized TDD tasks)

**Build strategy:** the app was ported one slice at a time; each slice is its own spec+plan. Slice 1 built the design system against mock data behind a repository seam; **from Slice 2 on everything is built against the live Firebase backend** (owner's directive — a live app, not a demo). There are no mocks in `lib/`; in-memory fakes in `test/support/fakes.dart` stand in for the repository interfaces in tests. New work follows the same pattern: spec in `docs/superpowers/specs/`, TDD plan in `docs/superpowers/plans/`, then build.

Current state (2026-10-25): **feature-complete; in launch prep.** All 33 prototype screens plus extras are built on live Firebase — Discover, Services (dynamic time slots; five pro types incl. Pet Behaviourist, plus **Home Brands** — a chat-to-order catalogue of local pet businesses, `brands/{uid}`, spec `2026-10-25-pawgo-behaviourist-home-brands-design.md`), Homestay, Community, chat, reviews, notifications (push + email engine), photos, maps, server-owned Razorpay payments/refunds/payouts (test mode), moderation, account deletion, back navigation, and email / Google / Apple / phone sign-in. Remaining work is launch work, mostly owner-side console and store steps: **`docs/launch-checklist.md`** is the single list. `plan.md` holds the phase-by-phase history; `docs/client-feedback-2026-10-setup.md` the console steps for the October round.

### Other workspaces

- `functions/` — Cloud Functions (TypeScript, Functions v2, region `asia-south1`). Payments, refunds, payouts, slot holds, account deletion, notification engine (`src/notify/`), moderation. Secrets live in Secret Manager. `npm --prefix functions test` (vitest), `npm --prefix functions run build` (tsc). Deploy: `firebase deploy --only functions,firestore:rules`. **Deploy Functions before shipping an app build that calls new/changed callables.**
- `admin/` — internal Next.js admin panel (Google SSO + `adminRoles` allowlist, audit log). `cd admin && npm run dev`; needs a service-account key in `admin/.env.local` (see `.env.local.example`). Not hosted yet.
- `codemagic.yaml` — iOS build → TestFlight, triggered by hand.

## Commands

```bash
flutter pub get                       # install deps
flutter run -d emulator-5554          # run on the Android emulator (or `flutter run` to pick a device)
flutter analyze                       # static analysis — must be clean before committing
flutter test                          # all tests
flutter test test/features/x_test.dart          # one file
flutter test --plain-name "substring of test"   # a single test by name
flutter build apk --debug             # full Android build (verifies native plugins compile)
flutter build apk --release           # signed release build (see the release-build gotcha below)
```

## Release signing

The app is **Pawgo Pets**. `applicationId` / iOS bundle ID is **`com.pawgopets.app`** on both platforms (renamed from `com.pawgo.app` before first publication — it is permanent from the moment a build reaches Play or App Store Connect, because both stores identify the app by it forever). Release builds are signed with `android/app/pawgo-release.jks` via `android/key.properties`. **Both files are git-ignored and exist only on the owner's machine** — losing either means never being able to publish an update. A clone without `key.properties` falls back to debug signing so the project still builds; that APK is not publishable. The keystore itself is unaffected by the rename — keystores are not bound to a package name.

The rename invalidates three things registered against the old ID, all owner-side: the Firebase Android + iOS apps (re-register, then re-download `google-services.json` / `GoogleService-Info.plist`), the "Pawgo Android Maps" key restriction, and the App Check Play Integrity registration.

## ⚠️ Windows build gotcha (do not remove the fix)

The project lives on `D:\` but the Flutter/Pub cache is on `C:\`. Kotlin's incremental compiler cannot relativise plugin sources across drive letters, so Kotlin-based Firebase plugins (`cloud_functions`, `firebase_app_check`, `firebase_storage`) fail with `IllegalArgumentException: this and base files have different roots` → `Daemon compilation failed`.

The fix is already in `android/gradle.properties`: **`kotlin.incremental=false`**. Keep it. If a newly added Kotlin plugin triggers a "different roots" error, confirm that line is present and run `flutter clean` before rebuilding to clear the half-written caches.

## ⚠️ Release-build gotcha: stale plugin registrant

`flutter pub get` writes `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` for **all** plugins including dev-dependencies. Release builds exclude dev-dependency plugins from the Gradle graph, so if that file is left over from a `pub get`, `flutter build apk --release` dies with:

```
error: package dev.flutter.plugins.integration_test does not exist
```

Delete the generated file and rebuild — `flutter build --release` regenerates it correctly for the build mode. `flutter clean` does **not** remove it (it lives under `src/main/`, not `build/`), which is what makes this easy to hit right after a clean + pub get.

## Architecture (the big picture)

The intended structure (from the Slice 1 plan) — feature-first under `lib/`:

- `core/theme/` — the design system translated from the prototype. `PgColors` (light/dark token sets, read via the `context.pg` extension), `PgText` (Poppins/Inter helpers via `google_fonts`), `PgRadius`/`PgGap`, and `PgTheme` (`ThemeData`). **All styling comes from these — screens never hard-code the palette except where the prototype uses one-off gradients.**
- `core/widgets/` — shared `Pg*` widgets (`PgPrimaryButton`, `PgChoiceCard`, `PgToggle`, `PgPageDots`, `PgChip`, `PgAppBar`, `PgImageSlot`, `PgBottomNav`, `PgScreenScaffold`). These encapsulate all styling, so screens are thin composition. Build/extend these before building screens.
- `core/router/` — `go_router`. Onboarding/auth are full-screen routes; Home + the four other tabs live inside a `StatefulShellRoute.indexedStack` that renders the persistent `PgBottomNav`. Route paths are constants in `routes.dart`.
- `features/<pillar>/` — one folder per pillar (onboarding, auth, pets, home, …). Screens compose `core/widgets` + read data from providers.
- `data/` — `models/` (plain Dart with Firestore `fromMap`/`toMap`: users, pets, pros, homestays, bookings, chats, posts, reviews, payments, notifications…), `repositories/` (**abstract interfaces**, ~18 of them, with Firebase-backed implementations under `repositories/firebase/`, all exposed via Riverpod providers in `providers.dart`), and `services/` (seams over SDKs: `PaymentService`/Razorpay, `PushService`, `ImagePickerService`). Each SDK is imported only by its one implementation file. In-memory fakes for every interface live in `test/support/fakes.dart`; `test/support/pump.dart` pumps the app with overrides.

**The key seam:** UI reads data only through repository interfaces provided by Riverpod. Slice 2 swaps the Slice 1 `Mock*` implementations for Firebase-backed ones at the provider layer — the backend is wired without changing any screen. Preserve this boundary; features depend on the interfaces, never on Firebase SDKs directly.

`lib/main.dart` initialises Firebase then `runApp(ProviderScope(child: PawgoApp()))`. `PawgoApp` (`lib/app.dart`) is a `MaterialApp.router` wired to the theme and router.

## Fidelity expectations

"Match the prototype" means a faithful re-implementation checked by eye against `Design/Pawgo Prototype.dc.html` (and the `screens/`-style renders), not a pixel-exact export. Intentional deviations: the prototype's browser phone-frame bezel and fake status bar are dropped (the real device fills the screen). Reproduce CSS animations with cheap Flutter equivalents; don't block a slice on pixel-perfection.
