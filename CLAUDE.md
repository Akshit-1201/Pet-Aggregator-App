# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Pawgo** — a Flutter + Firebase "pet aggregator" app (Android-only, Mumbai market). It bundles four products behind one account: Discovery/Matching ("Woof"), a Services marketplace, Homestay boarding, and a Community forum.

The entire UI already exists as a 30-screen prototype the owner designed in claude.ai/design. **We are porting that prototype into Flutter, not designing from scratch.** The prototype is the source of truth for every colour, font, radius and layout:

- `design/Pawgo Prototype.dc.html` — the full prototype (self-contained HTML; open in a browser to see the target). Design tokens live in its top `<style>` block (`--brand:#F59E2E`, cream `--bg:#FBF1E8`, Poppins + Inter, full light **and** dark themes).

## Working method (important)

This repo is built with the Superpowers spec → plan → execute workflow. Before implementing a feature, read its spec and plan:

- Specs: `docs/superpowers/specs/`
- Plans: `docs/superpowers/plans/` (bite-sized TDD tasks)

**Build strategy:** the app is ported one slice at a time; each slice is its own spec+plan. Slice 1 built the design system + onboarding/auth/Home UI against **mock data behind a repository seam**. **From Slice 2 on the app goes real** (owner's directive — it must be a live app, not a demo/mock): we wire the actual Firebase backend (Auth + Firestore) and build every feature against live data, with **no new mock stages**. Screens still depend only on repository interfaces (see architecture); we swap the mock implementations for Firebase-backed ones at the provider layer without touching UI. Maps and payments remain deferred to their own later slices.

Current state: **Slice 1 is built** (design system, `Pg*` widgets, models + mock repositories behind Riverpod, `go_router` shell + bottom nav, and all seven flow screens Splash→…→static Home — 20 widget tests, `flutter analyze` clean, runs on the emulator). **Slice 2 (in progress) makes the app real** — Firebase Auth (email/password) + a Firestore data layer replacing the mocks. Spec: `docs/superpowers/specs/2026-07-08-pawgo-real-backend-auth-firestore-design.md`. Slice 1 plan: `docs/superpowers/plans/2026-07-07-pawgo-foundation-onboarding.md`.

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

`applicationId` is **`com.pawgo.app`** (permanent — Play identifies the app by it forever). Release builds are signed with `android/app/pawgo-release.jks` via `android/key.properties`. **Both files are git-ignored and exist only on the owner's machine** — losing either means never being able to publish an update. A clone without `key.properties` falls back to debug signing so the project still builds; that APK is not publishable.

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
- `data/` — `models/` (plain Dart: `PetProfile`, `UserProfile`, `Role`, `Species`, with Firestore `fromMap`/`toMap`), and `repositories/` (**abstract interfaces** — `AuthRepository`, `UserRepository`, `PetRepository` — with Firebase-backed implementations under `repositories/firebase/`, exposed via Riverpod providers in `providers.dart`). In-memory fakes stand in for these interfaces in tests; the Slice 1 `mock/` data now serves only as a test fixture.

**The key seam:** UI reads data only through repository interfaces provided by Riverpod. Slice 2 swaps the Slice 1 `Mock*` implementations for Firebase-backed ones at the provider layer — the backend is wired without changing any screen. Preserve this boundary; features depend on the interfaces, never on Firebase SDKs directly.

`lib/main.dart` initialises Firebase then `runApp(ProviderScope(child: PawgoApp()))`. `PawgoApp` (`lib/app.dart`) is a `MaterialApp.router` wired to the theme and router.

## Fidelity expectations

"Match the prototype" means a faithful re-implementation checked by eye against `design/Pawgo Prototype.dc.html` (and the `screens/`-style renders), not a pixel-exact export. Intentional deviations: the prototype's browser phone-frame bezel and fake status bar are dropped (the real device fills the screen). Reproduce CSS animations with cheap Flutter equivalents; don't block a slice on pixel-perfection.
