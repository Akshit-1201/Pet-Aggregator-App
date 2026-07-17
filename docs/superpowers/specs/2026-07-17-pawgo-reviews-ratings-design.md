# Pawgo Slice 7c: Reviews & Ratings — Design

> **Status:** approved design (2026-07-17). Third of four sub-slices of Phase 7 (cross-cutting). Built on the live Firebase backend — **no mock data**. Rate a booking → a `reviews` collection + rating aggregation onto `pros`/`homestays`, making the "New"/`rating·reviewCount` real.

## Goal

Let a user **rate a booking** (a service booking with a pro, or a homestay booking with a host) with a 1–5 star rating and an optional comment. Each review is written to a `reviews` collection and **transactionally aggregated** onto the target's `rating`/`reviewCount` (both fields already exist on `Pro`/`Homestay`, defaulting to 0). The **Services list**, **Pro/Host profiles**, and their "New" badge become real. A new **My Bookings** list (reached from the Profile "Bookings" stat) is the entry point to rating; **Pro/Host profiles** show the real reviews.

Screens match `design/Pawgo Prototype.dc.html` (Rate & review 957–972; Pro reviews section ~614–620).

## Design decisions (settled during brainstorming)

- **Entry point = a "My Bookings" list.** The Profile "Bookings" stat becomes tappable → `/bookings`, listing the user's service bookings + homestay bookings. Each row offers a **Rate** action, or shows **"★ N"** once rated.
- **Both services and homestays are reviewable** — one shared review system with a `targetType` discriminator (`pro` | `homestay`). Aggregates land on `pros/{uid}` and `homestays/{uid}` respectively.
- **Any of your bookings can be rated exactly once.** No fake "completed" signal (service bookings only store a display-string date, and homestay bookings are still `requested` — the app has no completion tracking yet). Dedupe is structural: **`reviewId = bookingId`** (one review doc per booking; re-submit is idempotent).
- **A review = required 1–5 stars + optional comment.** No trait chips (they'd need a per-service-type tag taxonomy for little value now).
- **Rating aggregation = a Firestore transaction** that writes the review doc and updates the target's running average `rating` + `reviewCount` atomically. The list cards, "New" badge, and profile rating keep reading the pre-computed fields — no extra reads.
- **The `/rate` route carries a small `ReviewTarget` via `extra`** ({type, id, name, subtitle, bookingId}); the booking rows build it.
- **Deferred:** trait chips, edit/delete a review, review photos, replying to a review, sorting/filtering reviews, a real "completed" booking state.

## Scope

**In scope**
- `reviews/{id}` collection; `Review` model + `ReviewTargetType` enum + a `ReviewTarget` payload; `ReviewRepository` interface + Firestore impl (transactional aggregation) + in-memory fake; providers.
- **MyBookingsScreen** (services + homestays, Rate vs Rated) and **RateReviewScreen** (stars + comment + submit).
- Make the Profile "Bookings" stat tappable → `/bookings`; add a `myHomestayBookingsProvider`.
- **Pro-profile & Host-profile**: replace the static "No reviews yet." with a live reviews list; their rating badges now reflect real aggregates.
- `firestore.rules` for `reviews` + a rating/reviewCount-only `update` allowance on `pros`/`homestays`; deploy; routes.
- TDD with in-memory fakes; emulator integration test extended for a review round-trip + transactional aggregation.

**Out of scope (later)**
- Trait chips / structured review tags; edit or delete a review; review photos; replies to reviews; sorting/filtering reviews.
- A real "completed"/"done" booking lifecycle (host-accept, service-done) — a later slice.
- Moderation / reporting of reviews (Phase 12 admin).
- Secure server-side aggregation via a Cloud Function (functions are deferred project-wide) — see rules note.

## Firestore data model

```
reviews/{reviewId}                 // reviewId == bookingId (one review per booking)
  targetType : string 'pro' | 'homestay'
  targetId   : string (pro/host uid)          // the reviewed party
  targetName : string (denormalised display)
  authorId   : string (reviewer uid)
  authorName : string (denormalised)
  bookingId  : string (the rated booking id)
  stars      : int 1..5
  text       : string (optional comment)
  createdAt  : int millis

// aggregated onto the existing target docs (transaction):
pros/{uid}       .rating (double, running avg)  .reviewCount (int)
homestays/{uid}  .rating (double, running avg)  .reviewCount (int)
```

## Models (`lib/data/models/review.dart`)

- `enum ReviewTargetType { pro, homestay }` with a string wire value (`.wire` / `fromWire`), consistent with `ServiceType`/`HomeType`.
- `class Review { final String id, targetId, targetName, authorId, authorName, bookingId, text; final ReviewTargetType targetType; final int stars, createdAt; ... toMap/fromMap; }` — `id` is the doc id (= bookingId); `toMap` omits `id`.
- `class ReviewTarget { final ReviewTargetType type; final String id, name, subtitle, bookingId; }` — the lightweight payload passed to `/rate` via `extra` (built from a `Booking` or `HomestayBooking` row). Pure value object, not persisted.

## Repository seam

`lib/data/repositories/review_repository.dart`:
```dart
abstract interface class ReviewRepository {
  /// Transaction: if reviews/{bookingId} exists, no-op (idempotent); else
  /// write it AND bump the target's rating (running average) + reviewCount.
  Future<void> submitReview(Review review);
  /// A target's reviews, newest first.
  Stream<List<Review>> watchReviews(String targetId);
  /// Booking ids the user has already reviewed (to show Rate vs Rated).
  Stream<Set<String>> watchMyReviewedBookingIds(String uid);
}
```
- `FirestoreReviewRepository` under `repositories/firebase/`:
  - `submitReview` → `_db.runTransaction`: `tx.get(reviews/{bookingId})`; if it exists, return. Else read the target doc (`pros/{targetId}` or `homestays/{targetId}`), compute `newCount = reviewCount + 1`, `newRating = (rating*reviewCount + stars) / newCount`, then `tx.set(reviewRef, review.toMap())` and `tx.update(targetRef, {'rating': newRating, 'reviewCount': newCount})`. (The target doc is guaranteed to exist — you can only rate a booking you made from that listing.)
  - `watchReviews(targetId)` = `where('targetId', isEqualTo: targetId)` → sort by `createdAt` desc **client-side** (single-field query, **no composite index**).
  - `watchMyReviewedBookingIds(uid)` = `where('authorId', isEqualTo: uid)` → map to `{bookingId}` set.
- `InMemoryReviewRepository` fake in `test/support/fakes.dart` — stores reviews + maintains its **own** per-target aggregate map (`{rating, count}` keyed by `targetId`), bumped by `submitReview` (same running-average math) and exposed via an `({double rating, int count}) aggregateFor(String targetId)` getter for unit assertions. It does **not** depend on the `Pro`/`Homestay` fakes (the production impl bumps the real target docs; profile widget tests set a target's rating directly).
- Providers (`providers.dart`): `reviewRepositoryProvider`; `reviewsProvider` → `StreamProvider.autoDispose.family<List<Review>, String>` (by targetId); `myReviewedBookingIdsProvider` → `StreamProvider<Set<String>>` (empty when signed out); `myHomestayBookingsProvider` → `StreamProvider<List<HomestayBooking>>` (empty when signed out; mirrors `myBookingsProvider`).

## Screens (`features/reviews/`)

1. **MyBookingsScreen** (`ConsumerWidget`, route `/bookings`, reached from the Profile "Bookings" stat) — `PgAppBar` "My Bookings" + back. Lists the user's **service bookings** (`myBookingsProvider`) and **homestay bookings** (`myHomestayBookingsProvider`); each row: avatar, name (`proName` / `hostName`+`homeName`), a detail line (`serviceType.label · dateLabel` / `nights nights · check-in–check-out`), and a trailing **Rate** button, or **"★ N"** when `myReviewedBookingIdsProvider` contains that booking id. Tapping **Rate** → `context.push(Routes.rate, extra: ReviewTarget(...))`. Empty state ("No bookings yet — book a service or a homestay to get started."). Services and homestays render as two labelled groups (services first).
2. **RateReviewScreen** (`ConsumerStatefulWidget`, route `/rate`, `ReviewTarget` via `extra`) — header (back, "Rate your <walk/stay>"); avatar + `target.name` + `target.subtitle`; a row of five tappable ⭐ (state `_stars`, default 0; a caption maps 1→"Poor" … 5→"Excellent"); an optional multiline comment `PgTextField`; a "Submit review" button (disabled until `_stars >= 1`). **Submit** → build a `Review` (id = `target.bookingId`, denormalised names, `createdAt = now`) → `submitReview` → on success `context.pop()` + a "Thanks! Your review is live ⭐" snackbar; on error a failure snackbar and the button re-enables. Guards `mounted` after the await.

## Wiring, routes, rules

- **Profile** (`profile_screen.dart`): wrap the "Bookings" `_stat` in a `GestureDetector` → `context.push(Routes.bookings)`. (Pets/Woofs stats unchanged.)
- **Pro-profile** (`pro_profile_screen.dart`): replace the static "No reviews yet." with `ref.watch(reviewsProvider(p.uid))` — render each review (author, ★stars, text, time-ago via `Post.timeAgo`); keep "No reviews yet." only as the empty/`data([])` state. The rating badge (`reviewCount == 0 ? 'New' : '★ rating · N reviews'`) is already wired to the fields and now reflects real data. `ProProfileScreen` is already a `ConsumerWidget` (Slice 7b).
- **Host-profile** (`host_profile_screen.dart`): same — the "Recent reviews / No reviews yet." block becomes a live `reviewsProvider(homestay.uid)` list; make it a `ConsumerWidget` if it isn't already.
- **Routes:** `bookings = '/bookings'`, `rate = '/rate'` (top-level **protected**); `/rate` reads a `ReviewTarget` from `state.extra`.
- **`firestore.rules`** (deploy via CLI), after the `chats` block:
```
match /reviews/{reviewId} {
  allow read: if request.auth != null;
  allow create: if request.auth != null && request.resource.data.authorId == request.auth.uid;
  allow update, delete: if false;
}
```
  and add a rating-only `update` allowance to the existing `pros` and `homestays` blocks so the aggregation transaction (run by a non-owner reviewer) can bump only those two fields:
```
// inside match /pros/{uid} and match /homestays/{uid}, alongside the owner `allow write`:
allow update: if request.auth != null
              && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['rating', 'reviewCount']);
```
  **Rules note (soft):** this lets any authenticated user change `rating`/`reviewCount` on a target directly (not only through a genuine review). The proper fix is server-owned aggregation via a Cloud Function (deferred project-wide). Tracked with the existing rules-hardening follow-up; consistent with the codebase's current posture. `hasOnly(['rating','reviewCount'])` guarantees it cannot touch `verified` or other fields.

## Error handling

`RateReviewScreen`'s submit wraps `submitReview` in try/catch → an error snackbar and the button re-enables (improves on, rather than adds to, the tracked write-error follow-up). `ref.read`/`context` use after the await is `mounted`-guarded.

## Testing

TDD with in-memory fakes via `pumpPgApp` overrides:
- `Review` serialization round-trip; `ReviewTargetType.wire`/`fromWire`.
- `InMemoryReviewRepository`: `submitReview` writes the review + bumps the target's `rating` (running average across two reviews, e.g. 5 then 4 → 4.5) + `reviewCount`; **idempotent** on re-submit of the same bookingId (no double count); `watchReviews` newest-first; `watchMyReviewedBookingIds` returns the user's rated booking ids.
- **MyBookingsScreen**: lists a service booking + a homestay booking; a not-yet-rated booking shows **Rate**, a rated one shows **★ N**; empty state; tapping **Rate** opens the Rate screen.
- **RateReviewScreen**: renders target name/subtitle; submit is disabled at 0 stars; tapping a star then Submit writes a `Review` (correct target, stars, bookingId) that appears via `watchReviews`, and shows the "review is live" notice; a submit error shows a failure snackbar.
- **Pro-profile / Host-profile**: with a review present, the reviews list renders (author + text + ★) and the badge shows `★ rating · N reviews`; with none, "No reviews yet.".
- Profile "Bookings" stat → My Bookings (router); a My Bookings **Rate** → Rate screen (router).
- Extend `integration_test/firebase_repos_test.dart`: `submitReview` for a `pro` target → `watchReviews` reflects it, the `pros/{uid}` doc's `rating`/`reviewCount` update transactionally, and a re-submit is idempotent — against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live; `pros`/`homestays`/`bookings`/`homestayBookings` collections already exist. New rules deploy via the CLI.

## Deliverable / definition of done

From the Profile "Bookings" stat, a user opens **My Bookings**, taps **Rate** on a service or homestay booking, gives stars + an optional comment, and submits; the review appears on that pro's/host's profile and their `rating`/`reviewCount` (and "New" → "★ x · N reviews" badge) update for everyone; re-rating the same booking is a no-op. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
