# Pawgo Slice 12: Onboarding role-routing + optional pet — Design

> **Status:** approved design (2026-07-21). A pure UX/flow slice — no new collections, models, Firestore rules, or packages. Routes the last onboarding step by the role the user already chose, makes the pet step genuinely optional (with a skip), fixes a data-quality hole (blank-named junk pets), and replaces two silent dead buttons with honest empty states.

## Goal

Today every new user — pet parent, service pro, or homestay host — is forced through `Location → Create Pet → Home`, and `Create Pet` writes a pet even when every field is blank. A pro who owns no pet either abandons signup or plants an empty-named junk pet into everyone's Discovery deck and booking pickers. This slice routes onboarding by role, lets pros/hosts finish without a pet (adding one later via Profile), requires a real name before a pet is written, and gives the two booking flows a clear "add a pet first" path instead of a button that silently does nothing.

## Design decisions (settled during brainstorming)

- **Route by role after Location, listing-first for pros/hosts.** Pet parent → Create Pet (skippable); service pro → Pro setup; homestay host → Host setup. The role is already on the profile (written at signup), so `LocationScreen` reads it and routes. Pros/hosts add a pet later via the existing Profile "➕ Add a pet" card — no pet step in their onboarding.
- **Onboarding always terminates at Home.** Every terminal action in the signup chain — Create Pet Finish/Skip, Pro setup Save/Set-up-later, Host setup Save/Set-up-later — lands on `Routes.home` when reached during onboarding.
- **Listing setup is skippable.** Pro/host setup gets a "Set up later" secondary action → Home. A pro with no listing simply isn't shown in Services until they finish it; they can still browse and book as a normal user, and complete the listing anytime from Profile.
- **The setup screens are context-aware.** `ProSetupScreen`/`HostSetupScreen` are also reached *after* onboarding (Services "set up your services" banner, Profile "Become a pro or host"). In that context they must return to where they came from (Services list / Homestay list) exactly as today — only the onboarding entry exits to Home. Context is carried explicitly (a `fromOnboarding` flag), not inferred.
- **Create Pet requires a non-empty name + gains a skip.** "Finish" trims the name and blocks on empty with an inline error (closes the junk-pet hole independently of routing). A "Skip for now" secondary action → Home, writing nothing.
- **The two booking flows get honest empty states.** When `myPetsProvider` is empty, `BookingScreen` and `HomestayRequestScreen` replace their currently-silent no-op primary button with a message + a button to Create Pet. (Both screens already no-op safely with zero pets — this makes the dead end legible.)
- **Deferred / out of scope:** a dedicated "Do you have a pet? Yes/No" screen (the skippable Create Pet replaces the need); editing role after signup; any change to the pro/host listing forms themselves beyond the skip + exit target; onboarding progress indicators.

## Scope

**In scope**
- `LocationScreen._continue` — role-aware routing to Create Pet / Pro setup / Host setup.
- `CreatePetScreen` — name-required validation on Finish; a "Skip for now" action → Home.
- `ProSetupScreen` / `HostSetupScreen` — a `fromOnboarding` flag; a "Set up later" action; Save/skip exit to Home when onboarding, else to their list (current behaviour).
- `app_router.dart` — pass the `fromOnboarding` flag into the pro/host setup routes.
- `BookingScreen` / `HomestayRequestScreen` — "add a pet to book" empty state replacing the silent no-op button when petless.
- Widget tests for every routing branch, skip path, validation, exit target, and empty state.

**Out of scope (later)**
- No new Firestore collections, model fields, rules, or packages.
- No change to the pro/host listing form fields, the pet form fields, or the payment/booking backend.
- No "switch role" / multi-role support.

## Current behaviour (verified in code)

- `SignupScreen` writes `UserProfile(role: _role, area: '')` then `context.go(Routes.location)` (`signup_screen.dart:56-59`).
- `LocationScreen._continue` saves the area then unconditionally `context.go(Routes.createPet)` (`location_screen.dart:38`).
- `CreatePetScreen._finish` writes a `PetProfile` with `name: _name.text.trim()` and **no name validation**, then `context.go(Routes.home)` (`create_pet_screen.dart:59-102`).
- `ProSetupScreen._save` → `context.go(Routes.services)`; back → `context.go(Routes.services)` (`pro_setup_screen.dart:62,79`).
- `HostSetupScreen._save` → `context.go(Routes.homestay)`; back → `canPop() ? pop() : go(Routes.homestay)` (`host_setup_screen.dart:73,90-92`).
- `BookingScreen`: "Continue to payment" `onPressed: pets.isEmpty ? () {} : …` — silent no-op when petless (`booking_screen.dart:174`).
- `HomestayRequestScreen`: same silent-no-op pattern on "Send request".
- Profile already renders an "➕ Add a pet" card → `Routes.createPet` when `pets` is empty (`profile_screen.dart:115-128`) — the "add later" path already exists.

## Flow (after this slice)

```
Signup (role chosen) → Location (area saved)
    petParent    → Create Pet   → [Finish (name required)] or [Skip for now]      → Home
    servicePro   → Pro setup     → [Save listing]           or [Set up later]      → Home
    homestayHost → Host setup     → [Save listing]           or [Set up later]      → Home

Later, from Profile / Services banner (fromOnboarding = false):
    Pro setup  → [Save] / [back] → Services list   (unchanged)
    Host setup → [Save] / [back] → Homestay list   (unchanged)
    Add a pet (Profile card)     → Create Pet → [Finish] → Home / back  (unchanged path)
```

## Component changes

### `LocationScreen` (`lib/features/auth/location_screen.dart`)

`_continue`, after `updateArea` succeeds, reads the role and routes. The profile carries the role; read it from the already-watched `currentUserProfileProvider` (fall back to the freshly-saved value if the stream hasn't emitted). Mapping:

```dart
final role = ref.read(currentUserProfileProvider).value?.role ?? Role.petParent;
final target = switch (role) {
  Role.petParent => Routes.createPet,
  Role.servicePro => Routes.proSetup,
  Role.homestayHost => Routes.hostSetup,
};
if (mounted) context.go(target, extra: const OnboardingArg(fromOnboarding: true));
```

Create Pet needs to know it's in onboarding too (so it shows Skip and exits to Home). Pass the same flag. **`OnboardingArg`** is a tiny shared value type (`lib/features/auth/onboarding_arg.dart`: `class OnboardingArg { final bool fromOnboarding; const OnboardingArg({this.fromOnboarding = false}); }`) carried via go_router `extra`, so the three destination screens read one consistent thing. Screens reached by other routes get `extra == null` → treated as `fromOnboarding: false`.

### `CreatePetScreen` (`lib/features/pets/create_pet_screen.dart`)

- Accept `final bool fromOnboarding;` (default `false`) via constructor; the router reads it from `OnboardingArg`.
- **Name validation:** `_finish` computes `final name = _name.text.trim();` (already does) and, if empty, `setState` an inline `_nameError = 'Please enter your pet\'s name.'` and returns before any upload/write. Show the error under the name field. Clear it when the user types.
- **Skip:** when `fromOnboarding`, render a secondary "Skip for now" text action (below the Finish button) → `context.go(Routes.home)`, writing nothing. When not onboarding (opened from Profile), no Skip (they deliberately chose "Add a pet").
- Finish's success navigation stays `context.go(Routes.home)` (correct for both contexts — a pet was created).
- Back button: onboarding → `context.go(Routes.location)` (don't skip the area step); otherwise → `context.canPop() ? context.pop() : context.go(Routes.home)` (return to Profile when pushed from there). Today it hardcodes `context.go(Routes.signup)`, which is wrong in both contexts — this is a small correctness fix folded into a file we're already reworking.

### `ProSetupScreen` (`lib/features/services/pro_setup_screen.dart`)

- Accept `final bool fromOnboarding;` (default `false`).
- Exit target helper: `void _exit() => context.go(fromOnboarding ? Routes.home : Routes.services);`
- `_save` success → `_exit()` (was `context.go(Routes.services)`).
- Back button → `_exit()`.
- **Set up later:** when `fromOnboarding`, a secondary "Set up later" text action → `context.go(Routes.home)`, writing nothing. When not onboarding, no such action (the banner/Profile entry already implies intent, and Back exits to Services).

### `HostSetupScreen` (`lib/features/homestay/host_setup_screen.dart`)

- Accept `final bool fromOnboarding;` (default `false`).
- Exit target helper: `void _exit() => context.go(fromOnboarding ? Routes.home : Routes.homestay);`
- `_save` success → `_exit()` (was `context.go(Routes.homestay)`).
- Back button: onboarding → `_exit()`; otherwise keep `canPop() ? pop() : go(Routes.homestay)`.
- **Set up later:** when `fromOnboarding`, a secondary "Set up later" → `context.go(Routes.home)`, writing nothing.

### Router (`lib/core/router/app_router.dart`)

The `proSetup`, `hostSetup`, and `createPet` route builders read `state.extra as OnboardingArg?` and pass `fromOnboarding: arg?.fromOnboarding ?? false` to the screen. All three routes are already in `_protected`. No new routes.

### `BookingScreen` (`lib/features/services/booking_screen.dart`) & `HomestayRequestScreen`

When `pets.isEmpty`, replace the no-op primary button with an empty-state block in the bottom bar (or above it): text `Add a pet to book` (`Add a pet to send a request` for homestay) + a `PgPrimaryButton(label: 'Add a pet', onPressed: () => context.push(Routes.createPet))`. Using `push` (not `go`) so that after creating the pet the user returns to the booking screen with their new pet selectable. When `pets.isNotEmpty`, the existing button/behaviour is unchanged.

## Error handling

- Role read falls back to `Role.petParent` if the profile stream hasn't emitted — the safe default (worst case a pro briefly sees Create Pet, which is skippable).
- All skip/exit actions guard `context.mounted` (they follow no `await`, but the pattern is kept for the ones that do — save paths already do).
- Empty name blocks before any Storage upload or Firestore write — no partial writes.
- Booking empty-state `push` to Create Pet: creating a pet there writes normally; cancelling returns to the booking screen unchanged.

## Testing

Widget tests via `pumpPgApp` + in-memory fakes:
- **Routing:** signed-in user at `Routes.location`, each role in turn, tap Continue → lands on Create Pet / Pro setup / Host setup respectively (assert a screen-unique widget).
- **Create Pet:** Finish with a blank name → inline error shown, `InMemoryPetRepository` still empty, no navigation; Finish with a name → pet written, at Home. In onboarding, "Skip for now" → Home, repository empty. Not-onboarding entry (from Profile) → no Skip action present.
- **Pro/Host setup:** onboarding entry, "Set up later" → Home, no listing written; Save → Home. Non-onboarding entry, Save → Services/Homestay list (regression), Back → list.
- **Booking empty states:** petless user on Booking / Homestay-request → the "Add a pet" empty state renders; tapping it opens Create Pet; with a pet, the normal Continue/Send button renders (regression).
- Existing onboarding/signup/create-pet/pro-setup/host-setup tests updated for the new routing/flags where they assert navigation. `flutter analyze` clean; full suite green.

## Deliverable / definition of done

A new service pro signs up, picks their area, sets up (or skips) their listing, and reaches Home — never forced to invent a pet; a pet parent still adds a pet but can't create a blank-named one and can skip if they're not ready; a petless user tapping Book gets a clear "add a pet" step instead of a dead button; and the post-onboarding pro/host setup entries still return to their lists. `flutter analyze` clean, `flutter test` green, debug APK builds.
