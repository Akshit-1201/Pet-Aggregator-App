# Pawgo Slice 2: Go Real — Firebase Auth + Firestore Data Layer — Design

> **Status:** approved design (2026-07-08). Supersedes the original "all screens static/mock first, wire Firebase at Phase 8" strategy for everything from here on. The owner's directive: **the app must be a real, live app — not a demo or mock.**

## Goal

Turn the app delivered in Slice 1 (Splash → Onboarding → Welcome → Sign-up → Location → Create Pet → static Home) from **mock data** into a **live, Firebase-backed app**. Real accounts (Firebase Auth, email/password), real profiles and pets persisted in Cloud Firestore, and Home streaming real data — all by swapping implementations behind the existing Riverpod repository seam, so the Slice 1 UI is preserved.

This is the foundation that makes every later pillar real. **Discovery ("Woof") becomes the next slice, built directly against live Firestore — no mock stage.**

## Why this ordering

A real-time Discover deck requires a real signed-in user and real pet data to stream. Slice 1's auth/onboarding are display-only (static fields, no persistence). Building "real Discover" before real auth/profiles would put a real feature on a fake foundation. So the correct next step is: **real Auth → real profiles → real data layer**, then Discover on top.

## Scope

**In scope**
- Firebase **Auth** with **email/password**: sign-up, sign-in, sign-out, auth-state stream.
- **Firestore** collections `users/{uid}` and `pets/{petId}` with security rules.
- Slice 1 auth/onboarding screens become **real interactive forms** that create the account and persist profile + pet.
- **Auth-aware routing**: startup and `go_router` redirect driven by the real auth state.
- **Home** streams real nearby pets (`AsyncValue`: loading / empty / error / data); greeting uses the real user's name.
- Firestore **security rules** committed and deployed via the Firebase CLI.
- TDD throughout using **in-memory fakes** behind the repository interfaces (no network in tests).

**Out of scope (later phases)**
- Phone/OTP auth (needs Blaze plan + SHA fingerprints + Play Integrity/reCAPTCHA).
- Firebase **Storage** photo uploads (pets use the paw-slot avatar for now).
- Real **GPS/geolocation** and **Google Maps** (Nearby stays deferred to the Discover/Maps slices).
- **Cloud Functions**, FCM messaging, App Check enforcement.
- The **Discover** pillar itself (next slice) and all other pillars.

## Firestore data model

```
users/{uid}
  name       : string
  email      : string
  area       : string        // e.g. "Bandra West" (from Location step; free-typed/default for now)
  role       : string        // "petParent" | "servicePro" | "homestayHost"
  createdAt  : timestamp

pets/{petId}                 // petId = Firestore auto id
  ownerId    : string        // == users uid
  name       : string
  breed      : string
  species    : string        // "dog" | "cat" | "other"
  ageLabel   : string        // e.g. "2 yrs"
  sex        : string        // "male" | "female" (added for Discover cards later)
  area       : string
  vaccinated : bool
  createdAt  : timestamp
```

Models (`lib/data/models/`) gain `fromMap`/`toMap` (Firestore (de)serialization) and ids:
- `UserProfile`: add `uid`, `email`; `fromMap`/`toMap`.
- `PetProfile`: add `id`, `ownerId`, `sex`; `fromMap`/`toMap`. `accentColor` becomes a **derived** value (from species/name hash) rather than a stored field, so it is not persisted.
- `Role`/`Species`: add stable string keys for storage (`Role.storageKey`, `Species.storageKey`) + parse helpers.

## Architecture — the repository seam (unchanged boundary, new implementations)

UI keeps reading data only through abstract repositories provided by Riverpod. This slice adds interfaces + **Firebase implementations**, and swaps the providers.

```
lib/data/repositories/
  auth_repository.dart        // abstract AuthRepository
  user_repository.dart        // abstract UserRepository
  pet_repository.dart         // existing abstract PetRepository (extended)
  firebase/
    firebase_auth_repository.dart
    firestore_user_repository.dart
    firestore_pet_repository.dart
  providers.dart              // Riverpod providers wired to the Firebase impls
```

**`AuthRepository`**
- `Stream<AppUser?> authStateChanges()`
- `AppUser? get currentUser`
- `Future<AppUser> signUp({required String email, required String password})`
- `Future<AppUser> signIn({required String email, required String password})`
- `Future<void> signOut()`
- Throws a typed `AuthFailure` (mapped from `FirebaseAuthException` codes) so screens show friendly messages.
- `AppUser` is a tiny domain type (`uid`, `email`) so UI/tests never depend on the `firebase_auth` `User`.

**`UserRepository`**
- `Future<void> createUser(UserProfile profile)`
- `Future<void> updateArea(String uid, String area)`
- `Stream<UserProfile?> watchUser(String uid)`

**`PetRepository`** (extend existing)
- `Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId})`
- `Future<void> addPet(PetProfile pet)`
- `Stream<List<PetProfile>> watchMyPets(String ownerId)`
- The old synchronous `nearbyPets()` and `MockPetRepository` are removed from the app path (an in-memory fake remains for tests).

**Providers**
- `authRepositoryProvider` → `FirebaseAuthRepository`
- `authStateProvider` → `StreamProvider<AppUser?>` (from `authStateChanges()`)
- `userRepositoryProvider` → `FirestoreUserRepository`
- `currentUserProfileProvider` → `StreamProvider<UserProfile?>` (watches `users/{uid}` for the signed-in uid)
- `petRepositoryProvider` → `FirestorePetRepository`
- `nearbyPetsProvider` → `StreamProvider<List<PetProfile>>` (watches pets excluding the current uid)

## Screen changes (Slice 1 screens → real)

1. **SignupScreen** — replace display-only `PgField`s with real inputs (name, email, password) + the existing role selector. On **Continue**: `authRepository.signUp` → `userRepository.createUser` (uid, name, email, role; `area` empty for now, set at the Location step) → navigate to Location. Inline validation, a loading state on the button, and error surfacing (email in use, weak password, etc.). Introduces a `PgTextField` (real `TextFormField` styled like `PgField`).
2. **WelcomeScreen (login)** — real email/password inputs. On **Log in**: `authRepository.signIn` → redirect handles the move to Home. Friendly errors (wrong credentials). "Create account" → Sign-up.
3. **CreatePetScreen** — real inputs (pet name, breed, age, species, vaccinated). On **Finish**: `petRepository.addPet` with `ownerId = currentUser.uid` → Home. Photo upload deferred.
4. **LocationScreen** — calls `userRepository.updateArea(uid, area)` to persist the area onto the profile created at sign-up (a sensible default like "Bandra West"; a real place picker/GPS is deferred). Both buttons continue to Create Pet.
5. **SplashScreen** — instead of a fixed timer → onboarding, it waits for the first `authStateProvider` value and routes: signed-in → Home, else → Onboarding. (Keeps a minimum brand-visible delay for polish.)
6. **HomeScreen** — consumes `nearbyPetsProvider` as an `AsyncValue`: spinner while loading, a friendly empty state ("No pets nearby yet — check back soon"), an error state, and the pet list when data arrives. The greeting reads the real user's name from `currentUserProfileProvider` ("Hey {firstName} 👋").

## Auth-aware routing

- `go_router` gains a top-level `redirect` reading the latest auth state:
  - not signed in and heading into the shell/Home → redirect to `Welcome`.
  - signed in and on `Welcome`/`Signup`/`Onboarding` → redirect to `Home`.
- Router reacts to auth changes via a `refreshListenable` bridging the auth stream (`GoRouterRefreshStream`).
- Splash is exempt from the redirect while the first auth value resolves.

## Security rules (`firestore.rules`)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    match /pets/{petId} {
      allow read: if request.auth != null;                       // any signed-in user can browse pets (Home/Discover)
      allow create: if request.auth != null
                    && request.resource.data.ownerId == request.auth.uid;
      allow update, delete: if request.auth != null
                    && resource.data.ownerId == request.auth.uid;
    }
  }
}
```

- `firebase.json` gains a `firestore` section (`rules`, `indexes`); add `firestore.indexes.json` (empty to start).
- Deployed with `firebase deploy --only firestore:rules` (requires `firebase login`).

## Testing strategy (TDD, no real Firebase in tests)

Because all app code depends on the **interfaces**, tests use hand-written in-memory fakes — no network, no emulator, deterministic:
- `FakeAuthRepository` (in-memory user store, configurable to throw `AuthFailure`).
- `InMemoryUserRepository`, `InMemoryPetRepository` (backed by lists / `StreamController`s).
- Injected via `ProviderScope(overrides: [...])`. A new `pumpPgApp` test harness wraps a widget in `ProviderScope` + router + the Slice 1 phone-sized viewport.

Representative tests:
- Repository behaviour on the fakes (sign-up creates a user; addPet then watch emits it; watchNearbyPets excludes the owner).
- Signup form: empty fields block submit; a successful sign-up calls the auth + user repos and navigates.
- Login form: wrong credentials show an error; success routes to Home.
- Create Pet: submitting writes a pet with the current uid.
- Home: renders loading, empty, and populated states from an overridden `nearbyPetsProvider`.
- Router redirect: signed-out → Welcome; signed-in → Home.

The concrete `Firebase*Repository` classes are thin adapters (map ↔ model, collection queries) and are verified end-to-end on the emulator (they are not unit-tested against real Firebase in CI).

## Prerequisites (one-time, at implementation start)

Console actions on project `pet-aggregator-app` that cannot be scripted from here:
1. **Authentication → Sign-in method → enable Email/Password.**
2. **Firestore Database → create database** (Native mode; start in locked mode — our rules will be deployed).
3. `firebase login` in the terminal so rules can be deployed (`firebase deploy --only firestore:rules`).

Everything else (rules file, indexes, all Dart code, wiring, tests) is produced by the implementation.

## Risks / mitigations

- **Empty Home for a lone account.** With one real user, "pets near you" (which excludes your own) is legitimately empty. Mitigation: a proper empty state, and we create a couple of real test accounts to demo — real data, still not a mock.
- **firebase v6 test mocking.** Avoided entirely by testing against our own interfaces with in-memory fakes rather than `fake_cloud_firestore`/`firebase_auth_mocks` (which can lag major versions).
- **Windows cross-drive Kotlin build.** Unchanged; `kotlin.incremental=false` stays. No new Kotlin plugins are added in this slice.
- **Auth race on startup.** Splash gates on the first `authStateProvider` value before routing to avoid a flash of the wrong screen.

## Deliverable / definition of done

- Create an account (email/password), which persists `users/{uid}`; add a pet, which persists `pets/{petId}`; sign out and sign back in; the session survives an app restart; Home streams live pets with correct loading/empty/data states. `flutter analyze` clean, `flutter test` green (fakes), debug APK builds, and the flow is verified on the emulator against the real Firebase project.
