# Pawgo Slice 3: Discovery / "Woof" — Design

> **Status:** approved design (2026-07-08). Built on the live Firebase backend from Slice 2 — **no mock data**. Discover is the flagship pillar (bottom-nav tab 2, Home's primary CTA).

## Goal

Build the Discover / "Woof" pillar on live Firestore: a Tinder-style **drag-to-swipe card deck** of real nearby pets, real **Woof/Pass** actions persisted to Firestore, **reciprocal match** detection with an "It's a Woof match!" celebration, and a **Nearby** screen (stylised faux map + a bottom-sheet list of real nearby pets). Three screens, matching `design/Pawgo Prototype.dc.html` (lines 440–546).

## Scope

**In scope**
- `DiscoverScreen` — draggable card deck of live pets (excludes your own + anything you've already actioned), Pass/Woof/⭐ actions, empty state.
- `PgSwipeCard` — drag gesture with rotation, `PASS`/`WOOF!` overlays, threshold fling + spring-back; buttons animate too.
- Real **swipes** persisted to Firestore (`swipes` collection); **reciprocal-woof match** detection → `WoofMatchScreen` celebration.
- `NearbyMapScreen` — faux map (Flutter-drawn, **no google_maps**) + visual filter chips + bottom sheet listing real nearby pets with Woof buttons.
- `SwipeRepository` interface + Firestore impl behind Riverpod; `discoverDeckProvider` (nearby pets minus swiped).
- `firestore.rules` extended for `swipes` + a composite index; deployed.
- TDD with in-memory fakes; emulator integration test extended for swipe + reciprocity.

**Out of scope (later slices)**
- Pet photos / Firebase Storage (cards use the paw/emoji placeholder).
- Real Maps + geolocation + distance in km (Phase 9) — Nearby is a faux map; cards show `area`, not distance.
- Pet-profile detail screen and chat / matches list — links to them show a friendly "coming soon" snackbar.
- Cloud Functions, filter functionality (chips are visual), ⭐ "super-woof" as anything other than a normal Woof.
- A persisted `matches` collection (reciprocity is detected live; the durable match/chat record is the chat slice).

## Firestore data model

```
swipes/{swipeId}            // swipeId = "{fromUid}_{petId}" (deterministic → idempotent, no dup actions)
  fromUid    : string       // the swiper (== auth.uid)
  petId      : string       // the pet swiped
  ownerId    : string       // owner of that pet (for the reciprocity query)
  direction  : string       // "woof" | "pass"
  createdAt  : timestamp
```

- **Deck exclusion:** the deck shows pets from `watchNearbyPets(excludeOwnerId: me)` **minus** every `petId` present in my swipes.
- **Reciprocal match:** when I Woof a pet owned by `B`, match iff a swipe exists with `fromUid == B && ownerId == me && direction == 'woof'` (B already Woofed one of my pets). Detected client-side with a single query.

## Repository seam (unchanged boundary, new repo)

New `lib/data/repositories/swipe_repository.dart`:
```dart
enum SwipeDirection { woof, pass }
class Swipe { final String fromUid, petId, ownerId; final SwipeDirection direction; ... toMap(); }
abstract interface class SwipeRepository {
  Future<void> recordSwipe(Swipe swipe);
  Stream<Set<String>> watchSwipedPetIds(String uid);              // ids the user has already actioned
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid});
}
```
- `FirestoreSwipeRepository` under `repositories/firebase/`; `InMemorySwipeRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `swipeRepositoryProvider`; `discoverDeckProvider` (`StreamProvider<List<PetProfile>>`) = combine `nearbyPetsProvider` with `swipeRepository.watchSwipedPetIds(currentUid)` → pets whose `id` is not yet swiped.

## Components / screens

- **`PgSwipeCard`** (`core/widgets/`) — `{PetProfile pet, VoidCallback onWoof, VoidCallback onPass}`. Photo area (gradient + `PgImageSlot`), `PASS` (pink, rotate −14°) / `WOOF!` (amber, rotate +14°) overlays whose opacity tracks horizontal drag, `✓ Vaccinated` + `📍 {area}` chips, footer `name` + `age` then `breed · sex · area`. `GestureDetector` pan updates offset; rotation ∝ dx; on release past ±threshold, an `AnimationController` flings the card off and fires `onWoof`/`onPass`, else springs back. A small controller API lets the action buttons trigger the same fling.
- **`DiscoverScreen`** (`features/discovery/`, `ConsumerStatefulWidget`) — replaces the Discover tab `PlaceholderTab`. Header ("Discover" / "Pets near {profile.area}") + "⚙ Filters" → `/nearby`. Body: `discoverDeckProvider.when(loading/error/data)`; data → a stack of up to 2 static background card shells + the top `PgSwipeCard` for the current index. Woof → `recordSwipe(woof)` then `hasReciprocalWoof` → match ? `context.push('/woof-match', extra: pet)` : advance. Pass → `recordSwipe(pass)` → advance. Deck exhausted → "You're all caught up 🐾" empty state. Hint "Swipe right to Woof · left to pass".
- **`WoofMatchScreen`** (`features/discovery/`) — receives the matched `PetProfile` via go_router `extra`. Amber-gradient celebration ("It's a Woof match! 🎉", overlapping you+pet avatars with a paw badge, light pop/slide entrance). "Send a message 💬" → `showComingSoon(context, 'Chat')`; "Keep swiping" → `context.pop()`.
- **`NearbyMapScreen`** (`features/discovery/`) — faux map (positioned decorative shapes + teardrop emoji pins + a pulsing "you" dot, all Flutter widgets), search bar + horizontally-scrolling visual filter chips, and a bottom sheet: "N pets nearby" + rows (reuse the nearby-pets data) each with a Woof button (records a swipe) → row tap `showComingSoon('Pet profile')`; "Swipe view →" → back to `/discover`.
- **`showComingSoon(BuildContext, String label)`** (`core/widgets/`) — a shared SnackBar ("{label} is coming soon 🐾") for links into not-yet-built pillars.

## Routing

- Discover branch builder → `DiscoverScreen` (replaces `PlaceholderTab(title:'Discover')`).
- Add `Routes.nearby = '/nearby'` and `Routes.woofMatch = '/woof-match'` as top-level routes (both protected — require auth). `/woof-match` reads the pet from `state.extra`.
- Home's "See map →" and the Discover quick-action already point at `Routes.discover`; repoint "See map →" to `Routes.nearby`.

## Security rules + index

Add to `firestore.rules`:
```
match /swipes/{swipeId} {
  allow read: if request.auth != null
              && (resource.data.fromUid == request.auth.uid || resource.data.ownerId == request.auth.uid);
  allow create: if request.auth != null
              && request.resource.data.fromUid == request.auth.uid;
  allow update, delete: if false;   // swipes are immutable
}
```
`firestore.indexes.json` gains a composite index on `swipes` for the reciprocity query: `fromUid` (ASC), `ownerId` (ASC), `direction` (ASC). Deploy with `firebase deploy --only firestore:rules,firestore:indexes`.

## Testing strategy

TDD with in-memory fakes via `pumpPgApp` overrides (no network):
- `SwipeRepository` fake behaviour (record; watchSwipedPetIds emits; hasReciprocalWoof true only on a reciprocal woof).
- `discoverDeckProvider` excludes own + already-swiped pets.
- `PgSwipeCard`: a drag past threshold fires `onWoof`/`onPass` (simulate with `tester.drag`).
- `DiscoverScreen`: renders the first live pet; Woof on a non-reciprocal pet advances; Woof on a reciprocal pet navigates to the match screen; empty deck shows the caught-up state.
- `WoofMatchScreen`: shows heading + both buttons; "Send a message" shows the coming-soon snackbar.
- `NearbyMapScreen`: shows "pets nearby" + a pet row.
- Extend `integration_test/firebase_repos_test.dart` (emulators): record a swipe, verify `watchSwipedPetIds`, and that `hasReciprocalWoof` flips true after a reciprocal woof — with the new rules enforced.

## Prerequisites

None new — Firestore + Email/Password are already live (Slice 2). The new rules + index deploy via the CLI (already authenticated).

## Risks / mitigations

- **Deck goes empty with few accounts** — legitimate; a clear "all caught up" state, and we demo with two accounts (each Woofs the other → a real match).
- **Reciprocity query needs a composite index** — defined in `firestore.indexes.json` and deployed; the emulator/integration test exercises it.
- **Swipe gesture flakiness in tests** — assert via `onWoof`/`onPass` callbacks with `tester.drag` past a known threshold, not pixel-exact animation.
- **Reading others' swipes** — rules restrict `swipes` reads to the swiper or the target pet's owner, so the reciprocity query only sees permitted docs.

## Deliverable / definition of done

Swipe a live deck of real nearby pets; Woof/Pass persist to Firestore and the pet doesn't reappear; a reciprocal Woof between two accounts triggers the match celebration; Nearby shows a faux map + real nearby pets. `flutter analyze` clean, `flutter test` green (fakes), the emulator integration test passes with the new rules, debug APK builds, and the flow is verified on the emulator against the real project.
