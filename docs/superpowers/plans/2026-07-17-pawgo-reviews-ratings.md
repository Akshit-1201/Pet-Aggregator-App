# Pawgo Slice 7c: Reviews & Ratings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rate a booking (service or homestay) with 1–5 stars + an optional comment; each review writes to a `reviews` collection and is transactionally aggregated onto the target `pros`/`homestays` `rating`/`reviewCount`, and shows on Pro/Host profiles. A new My Bookings list (from the Profile "Bookings" stat) is the entry point.

**Architecture:** Feature-first Flutter on the existing repository seam. A `ReviewRepository` (interface + Firestore impl + in-memory fake) backs `reviews/{id}` (id = bookingId, one per booking) and a Firestore-transaction aggregation onto the target doc. Providers expose a target's reviews (`autoDispose.family`), the user's reviewed booking ids, and the user's homestay bookings. Two thin `Consumer` screens (My Bookings, Rate & Review) + a shared `ReviewsSection` widget. Leaf-first so navigation targets exist when tested.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`, `shared_preferences`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-17-pawgo-reviews-ratings-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **One review per booking:** `reviewId == bookingId`. `submitReview` is **idempotent** — re-submitting an existing booking's review is a no-op.
- **Rating aggregation = a Firestore transaction:** write the review doc + set the target's running-average `rating = (rating*count + stars)/(count+1)` and `reviewCount = count+1` atomically.
- **Enums** follow the codebase pattern: a `storageKey` field + `fromStorage(key)` (see `ServiceType`, `HomeType`).
- Timestamps are client `millisSinceEpoch` ints (consistent with `Post`/`Chat`). Reuse `Post.timeAgo(int)` for review time-ago.
- Riverpod 3.x: `AsyncValue.value` (not `valueOrNull`); `Override` from `package:flutter_riverpod/misc.dart` in tests; async handlers guard post-`await` state/context with `mounted`.
- `go_router` builders use `(_, _)`; routes reading `extra` use `(_, state)`. Screen tests use `pumpPgApp`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `Review` model + `ReviewTargetType` enum + `ReviewTarget` payload

**Files:**
- Create: `lib/data/models/review.dart`
- Test: `test/data/review_test.dart`

**Interfaces:**
- Produces: `enum ReviewTargetType { pro, homestay }` (`.storageKey`, `fromStorage`); `class Review` (fields `id, targetType, targetId, targetName, authorId, authorName, bookingId, stars, text, createdAt`; `toMap`/`fromMap`); `class ReviewTarget` (`type, id, name, subtitle, bookingId`).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/review_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/review.dart';

void main() {
  test('ReviewTargetType wire round-trips', () {
    expect(ReviewTargetType.pro.storageKey, 'pro');
    expect(ReviewTargetType.fromStorage('homestay'), ReviewTargetType.homestay);
    expect(ReviewTargetType.fromStorage('nonsense'), ReviewTargetType.pro); // fallback
  });

  test('Review round-trips through the map', () {
    const r = Review(id: 'b1', targetType: ReviewTargetType.homestay, targetId: 'host1',
        targetName: "Meera's Home", authorId: 'me', authorName: 'Radhika', bookingId: 'b1',
        stars: 5, text: 'Lovely stay', createdAt: 42);
    final back = Review.fromMap('b1', r.toMap());
    expect(back.targetType, ReviewTargetType.homestay);
    expect(back.targetId, 'host1');
    expect(back.stars, 5);
    expect(back.text, 'Lovely stay');
    expect(back.bookingId, 'b1');
    expect(back.createdAt, 42);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/review_test.dart`
Expected: FAIL — `Review`/`ReviewTargetType` not found.

- [ ] **Step 3: Implement `lib/data/models/review.dart`**

```dart
enum ReviewTargetType {
  pro('pro'),
  homestay('homestay');

  final String storageKey;
  const ReviewTargetType(this.storageKey);

  static ReviewTargetType fromStorage(String key) =>
      ReviewTargetType.values.firstWhere((t) => t.storageKey == key, orElse: () => ReviewTargetType.pro);
}

class Review {
  final String id, targetId, targetName, authorId, authorName, bookingId, text;
  final ReviewTargetType targetType;
  final int stars, createdAt;

  const Review({
    this.id = '',
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.authorId,
    required this.authorName,
    required this.bookingId,
    required this.stars,
    this.text = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'targetType': targetType.storageKey,
        'targetId': targetId,
        'targetName': targetName,
        'authorId': authorId,
        'authorName': authorName,
        'bookingId': bookingId,
        'stars': stars,
        'text': text,
        'createdAt': createdAt,
      };

  factory Review.fromMap(String id, Map<String, dynamic> m) => Review(
        id: id,
        targetType: ReviewTargetType.fromStorage((m['targetType'] ?? 'pro') as String),
        targetId: (m['targetId'] ?? '') as String,
        targetName: (m['targetName'] ?? '') as String,
        authorId: (m['authorId'] ?? '') as String,
        authorName: (m['authorName'] ?? '') as String,
        bookingId: (m['bookingId'] ?? '') as String,
        stars: (m['stars'] ?? 0) as int,
        text: (m['text'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}

/// Lightweight payload passed to the Rate screen via `extra` (built from a
/// Booking or HomestayBooking row). Not persisted.
class ReviewTarget {
  final ReviewTargetType type;
  final String id, name, subtitle, bookingId;
  const ReviewTarget({
    required this.type, required this.id, required this.name,
    required this.subtitle, required this.bookingId,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/review_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/review.dart
git add lib/data/models/review.dart test/data/review_test.dart
git commit -m "feat: add Review model + ReviewTargetType + ReviewTarget payload"
```

---

### Task 2: `ReviewRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/review_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryReviewRepository`)
- Test: `test/data/review_repository_test.dart`

**Interfaces:**
- Consumes: `Review`, `ReviewTargetType` (Task 1).
- Produces: `abstract interface class ReviewRepository { Future<void> submitReview(Review review); Stream<List<Review>> watchReviews(String targetId); Stream<Set<String>> watchMyReviewedBookingIds(String uid); }` and `InMemoryReviewRepository` (with an `({double rating, int count}) aggregateFor(String targetId)` getter for assertions).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/review_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import '../support/fakes.dart';

void main() {
  test('submitReview aggregates a running average, dedupes, and lists newest-first', () async {
    final repo = InMemoryReviewRepository();
    Review rev(String bookingId, int stars, int at) => Review(
        targetType: ReviewTargetType.pro, targetId: 'pro1', targetName: 'Aarav',
        authorId: 'me', authorName: 'Radhika', bookingId: bookingId, stars: stars, createdAt: at);

    await repo.submitReview(rev('b1', 5, 100));
    await repo.submitReview(rev('b2', 4, 200));
    expect(repo.aggregateFor('pro1').count, 2);
    expect(repo.aggregateFor('pro1').rating, 4.5); // (5 + 4) / 2

    // Re-submitting the same booking is a no-op.
    await repo.submitReview(rev('b1', 1, 300));
    expect(repo.aggregateFor('pro1').count, 2);

    final list = await repo.watchReviews('pro1').first;
    expect(list.map((r) => r.bookingId).toList(), ['b2', 'b1']); // newest first
    expect((await repo.watchMyReviewedBookingIds('me').first), {'b1', 'b2'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/review_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/review_repository.dart`**

```dart
import '../models/review.dart';

abstract interface class ReviewRepository {
  /// Idempotent (keyed by bookingId): writes the review + aggregates the
  /// running-average rating + reviewCount onto the target.
  Future<void> submitReview(Review review);
  Stream<List<Review>> watchReviews(String targetId);
  Stream<Set<String>> watchMyReviewedBookingIds(String uid);
}
```

- [ ] **Step 4: Add `InMemoryReviewRepository` to `test/support/fakes.dart`**

Add these imports next to the existing ones: `import 'package:pet_aggregator_app/data/models/review.dart';` and `import 'package:pet_aggregator_app/data/repositories/review_repository.dart';`. Then append (`dart:async` is already imported by the other fakes):

```dart
class InMemoryReviewRepository implements ReviewRepository {
  final Map<String, Review> _reviews = {};                    // keyed by reviewId (== bookingId)
  final Map<String, ({double rating, int count})> _agg = {};  // keyed by targetId
  final _ctrl = StreamController<List<Review>>.broadcast();

  ({double rating, int count}) aggregateFor(String targetId) =>
      _agg[targetId] ?? (rating: 0.0, count: 0);

  @override
  Future<void> submitReview(Review review) async {
    if (_reviews.containsKey(review.bookingId)) return; // idempotent
    _reviews[review.bookingId] = Review.fromMap(review.bookingId, review.toMap());
    final cur = aggregateFor(review.targetId);
    final newCount = cur.count + 1;
    final newRating = (cur.rating * cur.count + review.stars) / newCount;
    _agg[review.targetId] = (rating: newRating, count: newCount);
    _ctrl.add(_reviews.values.toList());
  }

  @override
  Stream<List<Review>> watchReviews(String targetId) async* {
    List<Review> forTarget() => _reviews.values.where((r) => r.targetId == targetId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield forTarget();
    yield* _ctrl.stream.map((_) => forTarget());
  }

  @override
  Stream<Set<String>> watchMyReviewedBookingIds(String uid) async* {
    Set<String> mine() =>
        _reviews.values.where((r) => r.authorId == uid).map((r) => r.bookingId).toSet();
    yield mine();
    yield* _ctrl.stream.map((_) => mine());
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/review_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data test/support/fakes.dart test/data/review_repository_test.dart
git add lib/data/repositories/review_repository.dart test/support/fakes.dart test/data/review_repository_test.dart
git commit -m "feat: add ReviewRepository interface + in-memory fake"
```

---

### Task 3: `FirestoreReviewRepository` (transactional aggregation)

**Files:**
- Create: `lib/data/repositories/firebase/firestore_review_repository.dart`

**Interfaces:**
- Consumes: `ReviewRepository`, `Review`, `ReviewTargetType` (Tasks 1–2).
- Produces: `FirestoreReviewRepository` (verified on the emulator in Task 11).

- [ ] **Step 1: Create `firestore_review_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/review.dart';
import '../review_repository.dart';

class FirestoreReviewRepository implements ReviewRepository {
  final FirebaseFirestore _db;
  FirestoreReviewRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('reviews');

  @override
  Future<void> submitReview(Review review) async {
    final reviewRef = _col.doc(review.bookingId); // one review per booking
    final targetCol = review.targetType == ReviewTargetType.pro ? 'pros' : 'homestays';
    final targetRef = _db.collection(targetCol).doc(review.targetId);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(reviewRef);
      if (existing.exists) return; // idempotent — the booking was already rated
      final targetSnap = await tx.get(targetRef);
      final data = targetSnap.data() ?? const <String, dynamic>{};
      final count = (data['reviewCount'] ?? 0) as int;
      final rating = ((data['rating'] ?? 0) as num).toDouble();
      final newCount = count + 1;
      final newRating = (rating * count + review.stars) / newCount;
      tx.set(reviewRef, review.toMap());
      tx.update(targetRef, {'rating': newRating, 'reviewCount': newCount});
    });
  }

  @override
  Stream<List<Review>> watchReviews(String targetId) => _col
      .where('targetId', isEqualTo: targetId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Review.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Stream<Set<String>> watchMyReviewedBookingIds(String uid) => _col
      .where('authorId', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => (d.data()['bookingId'] ?? '') as String).toSet());
}
```

Note: reads (`tx.get`) precede writes (`tx.set`/`tx.update`), as Firestore transactions require. The target doc is guaranteed to exist (you can only rate a booking made from that listing), so `tx.update` is safe.

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_review_repository.dart
git commit -m "feat: add FirestoreReviewRepository (transactional rating aggregation)"
```

---

### Task 4: Providers — reviews + my homestay bookings

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/review_providers_test.dart`

**Interfaces:**
- Produces: `reviewRepositoryProvider` → `Provider<ReviewRepository>`; `reviewsProvider` → `StreamProvider.autoDispose.family<List<Review>, String>`; `myReviewedBookingIdsProvider` → `StreamProvider<Set<String>>`; `myHomestayBookingsProvider` → `StreamProvider<List<HomestayBooking>>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/review_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('reviewsProvider streams a target reviews; myReviewedBookingIdsProvider tracks mine', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final reviews = InMemoryReviewRepository();

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(reviewsProvider('pro1'), (_, _) {}, fireImmediately: true);
    container.listen(myReviewedBookingIdsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: 'pro1',
        targetName: 'Aarav', authorId: uid, authorName: 'Me', bookingId: 'b1', stars: 5, createdAt: 1));
    await pumpEventQueue();
    expect((container.read(reviewsProvider('pro1')).value ?? []).length, 1);
    expect(container.read(myReviewedBookingIdsProvider).value, {'b1'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/review_providers_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add imports (near the other model/repository imports): `import '../models/homestay_booking.dart';`, `import '../models/review.dart';`, `import 'review_repository.dart';`, `import 'firebase/firestore_review_repository.dart';`. Then append:

```dart
final reviewRepositoryProvider = Provider<ReviewRepository>((ref) => FirestoreReviewRepository());

final reviewsProvider = StreamProvider.autoDispose.family<List<Review>, String>(
    (ref, targetId) => ref.watch(reviewRepositoryProvider).watchReviews(targetId));

final myReviewedBookingIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const {});
  return ref.watch(reviewRepositoryProvider).watchMyReviewedBookingIds(user.uid);
});

final myHomestayBookingsProvider = StreamProvider<List<HomestayBooking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(homestayBookingRepositoryProvider).watchMyHomestayBookings(user.uid);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/review_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/review_providers_test.dart
git commit -m "feat: add review providers + myHomestayBookingsProvider"
```

---

### Task 5: Route constants + `RateReviewScreen` + `/rate` route

**Files:**
- Create: `lib/features/reviews/rate_review_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `bookings`, `rate`)
- Modify: `lib/core/router/app_router.dart` (import + protect both + add `/rate` route)
- Test: `test/features/rate_review_screen_test.dart`

**Interfaces:**
- Consumes: `Review`, `ReviewTarget`, `ReviewTargetType`, `reviewRepositoryProvider`, `authRepositoryProvider`, `userRepositoryProvider`, `PgImageSlot`, `PgTextField`, `Routes`.
- Produces: `RateReviewScreen({ReviewTarget? target})`; `Routes.bookings == '/bookings'`, `Routes.rate == '/rate'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/rate_review_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('rating + submit writes a review and shows the notice', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final reviews = InMemoryReviewRepository();
    const target = ReviewTarget(type: ReviewTargetType.pro, id: 'pro1', name: 'Aarav Sharma',
        subtitle: 'Dog walk · Tue 15 Jul', bookingId: 'bk1');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.rate, extra: target);
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);
    await tester.tap(find.text('⭐').at(4)); // 5th star
    await tester.pump();
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();

    final list = await reviews.watchReviews('pro1').first;
    expect(list.single.stars, 5);
    expect(list.single.bookingId, 'bk1');
    expect(reviews.aggregateFor('pro1').rating, 5.0);
    expect(find.textContaining('review is live'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/rate_review_screen_test.dart`
Expected: FAIL — `RateReviewScreen` / routes not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `chat`):
```dart
  static const bookings = '/bookings';
  static const rate = '/rate';
```

- [ ] **Step 4: Implement `lib/features/reviews/rate_review_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';

class RateReviewScreen extends ConsumerStatefulWidget {
  final ReviewTarget? target;
  const RateReviewScreen({super.key, this.target});
  @override
  ConsumerState<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends ConsumerState<RateReviewScreen> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _submitting = false;

  static const _captions = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(ReviewTarget target, String myUid) async {
    if (_stars < 1 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final profile = await ref.read(userRepositoryProvider).watchUser(myUid).first;
      await ref.read(reviewRepositoryProvider).submitReview(Review(
          targetType: target.type, targetId: target.id, targetName: target.name,
          authorId: myUid, authorName: profile?.name ?? 'Someone', bookingId: target.bookingId,
          stars: _stars, text: _comment.text.trim(),
          createdAt: DateTime.now().millisecondsSinceEpoch));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (context.canPop()) context.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Thanks! Your review is live ⭐'),
          behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not submit your review. Please try again.'),
          behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final target = widget.target;
    if (target == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nothing to review')));
    }
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final canSubmit = _stars >= 1 && !_submitting;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 16, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: SizedBox(width: 40, height: 40, child: Icon(Icons.chevron_left, color: c.text))),
              Text('Rate your ${target.type == ReviewTargetType.homestay ? 'stay' : 'booking'}',
                style: PgText.poppins(18, FontWeight.w700, color: c.text)),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
            children: [
              Center(child: Column(children: [
                const PgImageSlot(size: 84, circle: true, emoji: '🧑'),
                const SizedBox(height: 13),
                Text(target.name, textAlign: TextAlign.center,
                  style: PgText.poppins(19, FontWeight.w800, color: c.text)),
                const SizedBox(height: 3),
                Text(target.subtitle, textAlign: TextAlign.center,
                  style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => setState(() => _stars = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Opacity(
                          opacity: i <= _stars ? 1 : 0.3,
                          child: const Text('⭐', style: TextStyle(fontSize: 40)))),
                    ),
                ]),
                const SizedBox(height: 6),
                Text(_captions[_stars], style: PgText.inter(13.5, FontWeight.w700, color: c.brand)),
              ])),
              const SizedBox(height: 22),
              PgTextField(label: 'Add a comment (optional)', controller: _comment,
                hint: 'Share how it went…', maxLines: 4),
            ],
          )),
          Container(
            padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: GestureDetector(
              onTap: canSubmit ? () => _submit(target, myUid) : null,
              child: Opacity(
                opacity: canSubmit ? 1 : 0.5,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]),
                    borderRadius: BorderRadius.circular(16)),
                  child: Text('Submit review', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)))),
            ),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the route + protect both constants in `app_router.dart`**

Add `import '../../data/models/review.dart';` and `import '../../features/reviews/rate_review_screen.dart';`; add `Routes.bookings, Routes.rate` to the `_protected` set; add this route (after the `Routes.chatList` route):
```dart
      GoRoute(path: Routes.rate, builder: (_, state) => RateReviewScreen(target: state.extra as ReviewTarget?)),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/rate_review_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/reviews/rate_review_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/rate_review_screen_test.dart
git commit -m "feat: add Rate & Review screen (stars + comment) + /rate route"
```

---

### Task 6: `MyBookingsScreen` + `/bookings` route

**Files:**
- Create: `lib/features/reviews/my_bookings_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/bookings` route)
- Test: `test/features/my_bookings_screen_test.dart`

**Interfaces:**
- Consumes: `myBookingsProvider`, `myHomestayBookingsProvider`, `myReviewedBookingIdsProvider`, `Booking`, `HomestayBooking`, `ReviewTarget`, `ReviewTargetType`, `PgAppBar`, `PgImageSlot`, `Routes`.
- Produces: `MyBookingsScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/my_bookings_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('lists services + homestays; Rate opens the Rate screen', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final bookings = InMemoryBookingRepository();
    await bookings.createBooking(Booking(id: 'bk1', parentId: uid, proId: 'pro1', proName: 'Aarav Sharma',
        petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23), nights: 3, subtotal: 2700,
        fee: 150, total: 2850));
    final reviews = InMemoryReviewRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('My Bookings'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('Rate'), findsNWidgets(2));

    await tester.tap(find.text('Rate').first);
    await tester.pumpAndSettle();
    expect(find.text('Submit review'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/my_bookings_screen_test.dart`
Expected: FAIL — `MyBookingsScreen` not found.

- [ ] **Step 3: Implement `lib/features/reviews/my_bookings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final services = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final stays = ref.watch(myHomestayBookingsProvider).value ?? const <HomestayBooking>[];
    final rated = ref.watch(myReviewedBookingIdsProvider).value ?? const <String>{};
    final empty = services.isEmpty && stays.isEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PgAppBar(title: 'My Bookings', onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
          Expanded(child: empty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text('No bookings yet — book a service or a homestay to get started.',
                  textAlign: TextAlign.center, style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (services.isNotEmpty) ...[
                    _sectionLabel(c, 'Services'),
                    for (final b in services)
                      _BookingRow(
                        emoji: '🧑', name: b.proName,
                        detail: '${b.serviceType.label} · ${b.dateLabel}',
                        rated: rated.contains(b.id),
                        onRate: () => context.push(Routes.rate, extra: ReviewTarget(
                          type: ReviewTargetType.pro, id: b.proId, name: b.proName,
                          subtitle: '${b.serviceType.label} · ${b.dateLabel}', bookingId: b.id)),
                      ),
                  ],
                  if (stays.isNotEmpty) ...[
                    _sectionLabel(c, 'Homestays'),
                    for (final s in stays)
                      _BookingRow(
                        emoji: '🏡', name: s.homeName,
                        detail: '${s.hostName} · ${s.nights} nights',
                        rated: rated.contains(s.id),
                        onRate: () => context.push(Routes.rate, extra: ReviewTarget(
                          type: ReviewTargetType.homestay, id: s.hostId, name: s.homeName,
                          subtitle: '${s.hostName} · ${s.nights} nights', bookingId: s.id)),
                      ),
                  ],
                ],
              )),
        ]),
      ),
    );
  }

  Widget _sectionLabel(PgColors c, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(text, style: PgText.poppins(14, FontWeight.w700, color: c.muted)),
      );
}

class _BookingRow extends StatelessWidget {
  final String emoji, name, detail;
  final bool rated;
  final VoidCallback onRate;
  const _BookingRow({required this.emoji, required this.name, required this.detail,
      required this.rated, required this.onRate});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        PgImageSlot(size: 46, circle: true, emoji: emoji),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
        const SizedBox(width: 10),
        if (rated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
            child: Text('★ Rated', style: PgText.inter(12.5, FontWeight.w700, color: c.brand)))
        else
          GestureDetector(
            onTap: onRate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [c.brand, c.brand2]), borderRadius: BorderRadius.circular(20)),
              child: Text('Rate', style: PgText.poppins(13, FontWeight.w700, color: Colors.white)))),
      ]),
    );
  }
}
```

- [ ] **Step 4: Add the `/bookings` route**

In `lib/core/router/app_router.dart`: add `import '../../features/reviews/my_bookings_screen.dart';` and this route (next to the `Routes.rate` route):
```dart
      GoRoute(path: Routes.bookings, builder: (_, _) => const MyBookingsScreen()),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/my_bookings_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/reviews/my_bookings_screen.dart lib/core/router/app_router.dart test/features/my_bookings_screen_test.dart
git commit -m "feat: add My Bookings list (services + homestays, Rate action) + /bookings route"
```

---

### Task 7: Profile "Bookings" stat → My Bookings

**Files:**
- Modify: `lib/features/profile/profile_screen.dart:52` (wrap the Bookings stat in a tap target)
- Test: `test/features/profile_bookings_nav_test.dart`

**Interfaces:**
- Consumes: `Routes.bookings`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/profile_bookings_nav_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('the Profile Bookings stat opens My Bookings', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('My Bookings'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/profile_bookings_nav_test.dart`
Expected: FAIL — tapping the stat does nothing (no navigation).

- [ ] **Step 3: Make the Bookings stat tappable**

In `lib/features/profile/profile_screen.dart`, the stats row (around line 52) has:
```dart
                Expanded(child: _stat(c, '${bookings.length}', 'Bookings')),
```
Replace that one line with:
```dart
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push(Routes.bookings),
                  child: _stat(c, '${bookings.length}', 'Bookings'))),
```
(`context`, `Routes`, and `context.push` are already available in `profile_screen.dart`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/profile_bookings_nav_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/features/profile/profile_screen.dart test/features/profile_bookings_nav_test.dart
git commit -m "feat: open My Bookings from the Profile Bookings stat"
```

---

### Task 8: `ReviewsSection` widget + real reviews on the Pro profile

**Files:**
- Create: `lib/features/reviews/reviews_section.dart`
- Modify: `lib/features/services/pro_profile_screen.dart:105` (swap static text for `ReviewsSection`)
- Test: `test/features/pro_reviews_test.dart`

**Interfaces:**
- Consumes: `reviewsProvider`, `Review`, `Post.timeAgo`, `PgColors`, `PgText`.
- Produces: `ReviewsSection({required String targetId})` — renders a target's reviews, or "No reviews yet." when empty.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/pro_reviews_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Pro profile shows real reviews + a rating badge', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4, rating: 5.0, reviewCount: 1);
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: 'pro1',
        targetName: 'Aarav Sharma', authorId: 'someone', authorName: 'Neha S.', bookingId: 'b1',
        stars: 5, text: 'So gentle with Bruno!', createdAt: 1));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.servicePro, extra: pro);
    await tester.pumpAndSettle();

    expect(find.text('Neha S.'), findsOneWidget);
    expect(find.textContaining('So gentle'), findsOneWidget);
    expect(find.textContaining('1 reviews'), findsOneWidget); // badge (reviewCount == 1)
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/pro_reviews_test.dart`
Expected: FAIL — the profile shows static "No reviews yet." (finds no 'Neha S.').

- [ ] **Step 3: Implement `lib/features/reviews/reviews_section.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';

/// The list of reviews for a pro/host, or "No reviews yet." when empty.
class ReviewsSection extends ConsumerWidget {
  final String targetId;
  const ReviewsSection({super.key, required this.targetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final reviews = ref.watch(reviewsProvider(targetId)).value ?? const <Review>[];
    if (reviews.isEmpty) {
      return Text('No reviews yet.', style: PgText.inter(13.5, FontWeight.w400, color: c.muted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final r in reviews) _ReviewTile(review: r)]);
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(review.authorName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.poppins(13.5, FontWeight.w700, color: c.text))),
          Text(List.filled(review.stars, '★').join(),
            style: PgText.inter(12.5, FontWeight.w700, color: c.brand)),
        ]),
        if (review.text.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(review.text, style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.45)),
        ],
        const SizedBox(height: 5),
        Text(Post.timeAgo(review.createdAt), style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]),
    );
  }
}
```

- [ ] **Step 4: Use `ReviewsSection` in `pro_profile_screen.dart`**

Add `import '../reviews/reviews_section.dart';` at the top. Replace the static reviews line (around line 105):
```dart
                    Text('No reviews yet.', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
```
with:
```dart
                    ReviewsSection(targetId: p.uid),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/pro_reviews_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/reviews/reviews_section.dart lib/features/services/pro_profile_screen.dart test/features/pro_reviews_test.dart
git commit -m "feat: show real reviews on the Pro profile (ReviewsSection)"
```

---

### Task 9: Real reviews on the Host profile

**Files:**
- Modify: `lib/features/homestay/host_profile_screen.dart:117` (swap static text for `ReviewsSection`)
- Test: `test/features/host_reviews_test.dart`

**Interfaces:**
- Consumes: `ReviewsSection` (Task 8).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/host_reviews_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Host profile shows real reviews', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const homestay = Homestay(uid: 'host1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK.', homeType: HomeType.apartment,
        ratePerNight: 900, rating: 5.0, reviewCount: 1);
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.homestay, targetId: 'host1',
        targetName: "Meera's Home", authorId: 'someone', authorName: 'Karan M.', bookingId: 'hb1',
        stars: 5, text: 'Bruno felt right at home.', createdAt: 1));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.host, extra: homestay);
    await tester.pumpAndSettle();

    expect(find.text('Karan M.'), findsOneWidget);
    expect(find.textContaining('felt right at home'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/host_reviews_test.dart`
Expected: FAIL — the profile shows static "No reviews yet.".

- [ ] **Step 3: Use `ReviewsSection` in `host_profile_screen.dart`**

Add `import '../reviews/reviews_section.dart';` at the top. Replace the static reviews line (around line 117):
```dart
                    Text('No reviews yet.', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
```
with:
```dart
                    ReviewsSection(targetId: h.uid),
```
(`HostProfileScreen` stays a `StatelessWidget`; `ReviewsSection` is itself a `ConsumerWidget`, so no ref is needed here. `h` is the non-null `Homestay` in scope.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/host_reviews_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/homestay/host_profile_screen.dart test/features/host_reviews_test.dart
git commit -m "feat: show real reviews on the Host profile"
```
Expected: whole suite green, analyze clean.

---

### Task 10: Firestore rules for `reviews` + rating-only target update; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `reviews` block + rating-only update to `pros`/`homestays`**

In `firestore.rules`, add the `reviews` block after the `chats` block (inside `match /databases/{database}/documents { ... }`):
```
    match /reviews/{reviewId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.authorId == request.auth.uid;
      allow update, delete: if false;
    }
```
Then, inside the existing `match /pros/{uid} { ... }` block, add a second `allow update` (alongside the owner `allow write`):
```
      allow update: if request.auth != null
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['rating', 'reviewCount']);
```
And the same inside `match /homestays/{uid} { ... }`:
```
      allow update: if request.auth != null
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['rating', 'reviewCount']);
```
(This lets the review transaction — run by a non-owner reviewer — bump only `rating`/`reviewCount`; `hasOnly` prevents touching `verified` or other fields. Soft rule; hardening tracked with the rules follow-up.)

- [ ] **Step 2: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `Deploy complete!`

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "chore: add + deploy Firestore rules for reviews + rating-only target update"
```

---

### Task 11: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a reviews round-trip + aggregation test)

- [ ] **Step 1: Append a reviews test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/review.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_review_repository.dart';` with the other imports, then add this `testWidgets` inside `main()`:
```dart
  testWidgets('reviews submit + aggregate transactionally + idempotent (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final pros = FirestoreProRepository();
    final reviews = FirestoreReviewRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // The pro owns their listing doc (rules require uid == doc id to create it).
    final proAcct = await auth.signUp(email: 'proacct_$stamp@x.com', password: 'secret1');
    await pros.upsertPro(Pro(uid: proAcct.uid, name: 'Aarav', area: 'Bandra West', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    await auth.signOut();

    // A different user (the reviewer) rates a booking with this pro.
    final me = await auth.signUp(email: 'rev_$stamp@x.com', password: 'secret1');
    Review review(int stars) => Review(targetType: ReviewTargetType.pro, targetId: proAcct.uid,
        targetName: 'Aarav', authorId: me.uid, authorName: 'Radhika', bookingId: 'bk_$stamp',
        stars: stars, text: 'Great', createdAt: stamp);

    await reviews.submitReview(review(5));
    final list = await reviews.watchReviews(proAcct.uid).firstWhere((l) => l.isNotEmpty);
    expect(list.single.stars, 5);
    final after = await pros.watchPro(proAcct.uid).firstWhere((p) => p != null && p.reviewCount == 1);
    expect(after!.reviewCount, 1);
    expect(after.rating, 5.0);
    expect(await reviews.watchMyReviewedBookingIds(me.uid).firstWhere((s) => s.isNotEmpty),
        contains('bk_$stamp'));

    // Re-submitting the same booking is a no-op (transaction sees the existing review).
    await reviews.submitReview(review(1));
    final again = await pros.watchPro(proAcct.uid).first;
    expect(again!.reviewCount, 1); // unchanged

    await auth.signOut();
  });
```

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # another
```
Expected: all integration tests pass. (Reuse a running emulator if one is up on 8080/9099; if the Pixel_10 AVD is offline, kill stale `qemu`/`emulator` processes, delete `~/.android/avd/Pixel_10.avd/*.lock`, and cold-boot `emulator -avd Pixel_10 -no-snapshot-load`.) Stop the emulators after if you started them.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds.

- [ ] **Step 4: Manual walkthrough (real cloud)**

Run: `flutter run -d emulator-5554`. From **Profile → Bookings**, open **My Bookings**, tap **Rate** on a service or homestay booking, give stars + an optional comment, submit → the review appears on that pro's/host's profile and the badge updates ("New" → "★ x · N reviews"); re-opening My Bookings shows **★ Rated** for that booking; re-rating the same booking does not double-count.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify reviews round-trip + transactional aggregation against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `reviews` collection + `Review`/`ReviewTargetType`/`ReviewTarget` → Task 1. ✓
- `ReviewRepository` + fake + Firestore (transaction) + providers → Tasks 2–4. ✓
- Rate & Review screen (stars + comment, error-guarded submit) → Task 5; My Bookings list (services + homestays, Rate vs Rated) → Task 6. ✓
- Profile "Bookings" stat entry → Task 7. ✓
- Real reviews on Pro + Host profiles (shared `ReviewsSection`) → Tasks 8–9. ✓
- Rules (`reviews` + rating-only target update) + deploy → Task 10; emulator integration (round-trip + aggregation + idempotence) → Task 11. ✓
- Deferred (trait chips, edit/delete, photos, replies, sorting, "completed" lifecycle) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. `reviewsProvider` is `autoDispose.family`. Timestamps are client ints. Aggregation is a transaction with reads-before-writes + idempotence.

**Type consistency:**
- `Review` fields + `ReviewTargetType.storageKey`/`fromStorage` + `ReviewTarget` identical across Task 1 (model), Task 2 (fake/tests), Tasks 5–6 (screens), Tasks 8–9 (section), Task 11 (integration). ✓
- `ReviewRepository` methods (`submitReview`, `watchReviews`, `watchMyReviewedBookingIds`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), providers (Task 4), and callers (Tasks 5–9, 11). ✓
- Providers (`reviewRepositoryProvider`, `reviewsProvider`, `myReviewedBookingIdsProvider`, `myHomestayBookingsProvider`) defined Task 4, consumed Tasks 5–9. ✓
- `Routes.bookings`/`Routes.rate` added Task 5 (+ `_protected` + `/rate` route), `/bookings` route Task 6, consumed Task 6 (row push `rate`), 7 (push `bookings`). ✓
- `ReviewsSection({targetId})` defined Task 8, consumed Tasks 8 (pro) + 9 (host). ✓
- Existing APIs reused with verified signatures: `myBookingsProvider`, `homestayBookingRepositoryProvider`, `authStateProvider`, `Booking.{proId,proName,serviceType,dateLabel,id}`, `HomestayBooking.{hostId,homeName,hostName,nights,id}`, `Pro.{uid,rating,reviewCount}`, `Homestay.{uid,rating,reviewCount}`, `PgAppBar(title,onBack)`, `PgTextField(label,controller,hint,maxLines)`, `PgImageSlot(size,circle,emoji)`, `Post.timeAgo(int)`, the in-memory fakes' method names, and the booking fakes preserving the provided `id`. ✓
