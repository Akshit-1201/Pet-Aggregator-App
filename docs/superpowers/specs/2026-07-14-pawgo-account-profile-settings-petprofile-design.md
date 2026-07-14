# Pawgo Slice 7a: Account — Profile + Settings + Pet-profile — Design

> **Status:** approved design (2026-07-14). First of four sub-slices of Phase 7 (cross-cutting/shared screens). Built on the live Firebase backend — **no mock data**. Completes the last placeholder bottom-nav tab (Profile) and the read-only Pet-profile detail the app links to.

## Goal

Stand up the account/profile cluster: the **Profile tab** (real user data, own pet, real stats, menu, sign-out), a **Settings** screen with a **real dark-mode toggle** (persisted), and the read-only **Pet-profile detail** that Discover/Home/Profile link to (replacing the current "coming soon" stubs). Reuses `users`/`pets`/`bookings`/`swipes` — no new Firestore collections.

Screens match `design/Pawgo Prototype.dc.html` (Profile 904–927, Settings 930–955, Pet profile 975–989).

## Design decisions (settled during brainstorming)

- **Dark mode is real and persisted via `shared_preferences`** (the first new package since Slice 1). The app already ships a full `PgTheme.dark()`; only the toggle + persistence are missing (`app.dart` hardcodes `themeMode: ThemeMode.light`).
- **Pet-profile displays existing `PetProfile` fields only** — no new model fields, no Create-pet changes. The prototype's size/energy/temperament tiles are replaced with real facts (Species / Sex / Vaccinated); the "About" paragraph is omitted.
- **All three Profile stats are real** (Pets / Bookings / Woofs) — via small provider/repo additions, not faked or dropped.
- **Only Dark mode is an interactive setting** this slice; notification/privacy rows are honest "coming soon" (FCM, location controls, chat safety land later), not fake toggles.
- **"Send a Woof" from another pet's profile records a real woof** (reuses `SwipeRepository`); your own pet shows no woof button.

## Scope

**In scope**
- `shared_preferences` package; a `PreferencesRepository` seam (interface + `SharedPreferencesRepository` impl + in-memory fake) for the theme mode; `preferencesRepositoryProvider`; `themeModeProvider`; `app.dart`/`main.dart` wiring.
- **ProfileScreen** (replaces `PlaceholderTab('Profile')`), **SettingsScreen**, **PetProfileDetailScreen**.
- Small data additions: `SwipeRepository.watchMyWoofCount`, `myWoofCountProvider`, `myBookingsProvider`, `userByIdProvider` (family).
- Routes (`settings`, `petProfile`); Profile branch wiring; rewire pet-profile entry points (Profile own-pet card, Home pet rows); real sign-out.
- TDD with in-memory fakes; the dark-mode persistence path covered by a prefs-fake unit test.

**Out of scope (later)**
- Photo uploads (avatar/pet photo — Storage); the edit badge is decorative.
- FCM push + notification preference toggles; location-sharing controls; chat-safety config (rows are coming-soon).
- "My bookings" / "My homestays" / "Payments & wallet" list screens, "Become a pro/host" flow entry (menu rows are coming-soon).
- Reviews/ratings on the owner card (the ★ rating is omitted — Slice 7c).
- Editing the user profile (name/area edit); Chat (7b), Notifications (7d).

## New infra — dark mode

`lib/data/repositories/preferences_repository.dart`:
```dart
abstract interface class PreferencesRepository {
  ThemeMode get themeMode;                 // ThemeMode.system if unset
  Future<void> setThemeMode(ThemeMode mode);
}
```
- `SharedPreferencesRepository(SharedPreferences prefs)` under `repositories/local/` — stores a `'themeMode'` string (`'light'|'dark'|'system'`).
- `InMemoryPreferencesRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `preferencesRepositoryProvider` (default `throw UnimplementedError('override in main')`, overridden in `main.dart` after prefs load; overridden with the fake in tests); `themeModeProvider` → `NotifierProvider<ThemeModeNotifier, ThemeMode>` whose `build()` returns `ref.read(preferencesRepositoryProvider).themeMode` and whose `setThemeMode(mode)` sets `state` then persists via the repo (plus a `toggleDark(bool)` helper).
- `lib/app.dart`: `themeMode: ref.watch(themeModeProvider)` (was `ThemeMode.light`).
- `lib/main.dart`: after `Firebase.initializeApp`, `final prefs = await SharedPreferences.getInstance();` then `runApp(ProviderScope(overrides: [preferencesRepositoryProvider.overrideWithValue(SharedPreferencesRepository(prefs))], child: const PawgoApp()))`.
- **Windows note:** `shared_preferences_android` is a Kotlin plugin — the existing `kotlin.incremental=false` in `android/gradle.properties` covers the cross-drive build; run `flutter clean` if a stale build errors.

## Small data additions

- `SwipeRepository.watchMyWoofCount(String uid) → Stream<int>` — Firestore impl queries `where('fromUid', ==, uid)` and maps to the count of `direction == woof` (client-side filter → **no new composite index**); fake counts woof swipes for `fromUid`. `myWoofCountProvider` → `StreamProvider<int>` (0 when signed out).
- `myBookingsProvider` → `StreamProvider<List<Booking>>` wrapping `bookingRepository.watchMyBookings(uid)` (service bookings; empty when signed out).
- `userByIdProvider` → `StreamProvider.family<UserProfile?, String>((ref, uid) => userRepository.watchUser(uid))` — for the Pet-profile owner card.

## Screens

1. **ProfileScreen** (`ConsumerWidget`, replaces `PlaceholderTab('Profile')`, the Profile tab) — amber gradient header; a profile card (avatar placeholder + decorative edit badge, `profile.name`, `${role.label} · ${area}`, a 3-stat row: **Pets** = `myPetsProvider.length`, **Bookings** = `myBookingsProvider.length`, **Woofs** = `myWoofCountProvider`); an **own-pet card** (first of `myPetsProvider`) → `push(petProfile, extra: pet)`, or an "Add a pet" row → `Routes.createPet` when none; a menu group (My bookings / My homestays / Payments & wallet / Become a pro or host → `showComingSoon`); a second group with **Settings** → `push(settings)` and **Sign out** → `authRepository.signOut()` (the auth-aware redirect returns to Welcome). Loading/empty handled via `AsyncValue`.
2. **SettingsScreen** (`ConsumerWidget`) — `PgAppBar('Settings')`; **APPEARANCE**: a "Dark mode" row with a real toggle (`PgToggle`) bound to `themeModeProvider` (`dark` vs `light`; `set/toggleDark` persists); **NOTIFICATIONS** (New Woofs & matches / Booking updates / Nearby pet alerts) and **PRIVACY & ACCOUNT** (Location sharing / Chat safety / About Pawgo `v1.0.0`) rendered as rows that `showComingSoon` on tap (About shows the static version) — not fake toggles.
3. **PetProfileDetailScreen** (`ConsumerWidget`, `PetProfile` via `extra`) — photo placeholder + back; a card (name, sex symbol from `sex`, `breed · ageLabel · area`, a "✓ Vaccinated" badge when `vaccinated`); a 3-tile trait row from real fields (Species `emoji+label` / Sex / Vaccinated Yes-No); an owner card (owner name via `userByIdProvider(pet.ownerId)`, "Pet parent" label; ★ rating omitted this slice); bottom CTA — if `pet.ownerId == currentUid` **no button** (it's your pet); else **"Send a Woof 👋"** → `swipeRepository.recordSwipe(Swipe(fromUid, petId, ownerId, woof))` + a "You woofed {name}! 🐾" snackbar.

## Routing & wiring

- Add `Routes.settings = '/settings'` and `Routes.petProfile = '/pet-profile'` as top-level **protected** routes; `/pet-profile` reads a `PetProfile` from `state.extra`. Profile branch builder → `ProfileScreen`.
- Rewire pet-profile entry points to `push(petProfile, extra: pet)`: the Profile own-pet card and the Home pet rows (`home_screen.dart` / `PetRow`) — replacing any current no-op/coming-soon.
- No Firestore rules change (reuses `users`/`pets`/`bookings`/`swipes`, all already owner-scoped; `watchMyWoofCount`'s `where fromUid==uid` is permitted by the existing `swipes` read rule and needs no new index).

## Testing

TDD with in-memory fakes via `pumpPgApp`/`pumpPg` overrides:
- `InMemoryPreferencesRepository` + `themeModeProvider`: `build()` returns the saved mode; `setThemeMode`/`toggleDark` flips `state` **and** persists (assert the fake round-trips).
- `SwipeRepository.watchMyWoofCount` fake: counts only `woof` swipes for the uid; `myWoofCountProvider` streams it.
- `ProfileScreen`: renders `name`/`role·area` + the own-pet card + the three real stats; "Sign out" calls `signOut`; menu rows → coming-soon; no pet → "Add a pet".
- `SettingsScreen`: the Dark mode toggle flips `themeModeProvider` (assert the mode changed and the fake persisted); coming-soon rows snackbar.
- `PetProfileDetailScreen`: renders fields + "✓ Vaccinated"; own pet hides the woof button; another user's pet shows "Send a Woof" and tapping it calls `recordSwipe`.
- `userByIdProvider` streams a user profile.
- Router: Profile tab renders `ProfileScreen`; own-pet card → Pet-profile; Settings route; a Home pet row → Pet-profile.
- Extend `integration_test/firebase_repos_test.dart`: `watchMyWoofCount` reflects a recorded woof against the Firestore emulator.

## Prerequisites

None new for the cloud — Firestore/Auth are live. Adds the `shared_preferences` package (`flutter pub get`; a full rebuild picks up the native plugin).

## Deliverable / definition of done

The Profile tab shows the signed-in user's real name/role/area, own pet, and real Pets/Bookings/Woofs counts; Settings toggles dark mode and it **persists across app restarts**; tapping a pet (from Profile or Home) opens the read-only Pet-profile detail, where another user's pet can be woofed; Sign out works. `flutter analyze` clean, `flutter test` green (fakes), the emulator integration test passes, debug APK builds.
