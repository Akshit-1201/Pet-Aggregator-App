# Pawgo Slice 7d: Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An in-app Notifications feed (🔔 bell on Home with an unread dot) **derived** from the user's existing data — unread messages, reviews received, and their bookings/homestay requests — with a "Mark all read" cursor and deep-links.

**Architecture:** No new collection, no cross-user writes, no rules change. A pure `buildNotifications(...)` function maps four existing streams into `NotificationItem` view-models; `notificationsProvider` combines the sources + a per-user `notifsSeenAt` cursor and flags read/unread. A thin `Consumer` screen + a Home-header bell. Bookings gain an additive client-int `createdAt` for ordering.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`, `shared_preferences`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-18-pawgo-notifications-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, `integration_test/`. **Models must NOT import `cloud_firestore`** (no `Timestamp` in models).
- **Derived feed only** — no `notifications` collection, no actor-writes, no new `firestore.rules`. All four sources are already readable by the owner; `notifsSeenAt` lives on the user's own doc.
- **Client `millisSinceEpoch` int timestamps** (consistent with `Post`/`Chat`/`Review`). `createdAt` on `Booking`/`HomestayBooking` becomes a client int (replacing the old unused `serverTimestamp()` write); `fromMap` reads it defensively (`is int ? … : 0`) so any stale `Timestamp` doc degrades to 0.
- **Unread = a single cursor** `UserProfile.notifsSeenAt`; an item is unread when `timestamp > notifsSeenAt`. **Mark all read** sets it to `now`. Opening the screen does not auto-clear.
- Riverpod 3.x: `AsyncValue.value` (not `valueOrNull`); `Override` from `package:flutter_riverpod/misc.dart` in tests. `go_router` builders use `(_, _)`; routes reading `extra` use `(_, state)`. Screen tests use `pumpPgApp`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `createdAt` on `Booking` + `HomestayBooking`

**Files:**
- Modify: `lib/data/models/booking.dart`, `lib/data/models/homestay_booking.dart`
- Modify: `lib/data/repositories/firebase/firestore_booking_repository.dart`, `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`
- Modify: `test/support/fakes.dart` (`InMemoryBookingRepository`, `InMemoryHomestayBookingRepository`)
- Test: `test/data/booking_createdat_test.dart`

**Interfaces:**
- Produces: `Booking.createdAt` (int, default 0) + `HomestayBooking.createdAt` (int, default 0); both repos' `create*` stamp `createdAt = now` when unset; `fromMap` reads `createdAt` defensively.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/booking_createdat_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

Booking _booking({int createdAt = 0}) => Booking(id: 'bk1', parentId: 'me', proId: 'p1',
    proName: 'Aarav', petId: 'x', petName: 'Bruno', serviceType: ServiceType.walker,
    rate: 250, fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', createdAt: createdAt);

void main() {
  test('Booking.createdAt round-trips; stale non-int degrades to 0', () {
    expect(Booking.fromMap('bk1', _booking(createdAt: 42).toMap()).createdAt, 42);
    expect(Booking.fromMap('bk1', {'createdAt': 'not-an-int'}).createdAt, 0); // defensive guard
  });

  test('createBooking stamps createdAt when unset, preserves when set', () async {
    final repo = InMemoryBookingRepository();
    await repo.createBooking(_booking()); // createdAt 0 -> stamped
    final stamped = (await repo.watchMyBookings('me').first).single;
    expect(stamped.createdAt, greaterThan(0));

    final repo2 = InMemoryBookingRepository();
    await repo2.createBooking(_booking(createdAt: 500));
    expect((await repo2.watchMyBookings('me').first).single.createdAt, 500);
  });

  test('HomestayBooking.createdAt round-trips + fake stamps', () async {
    final hb = HomestayBooking(id: 'hb1', guestId: 'me', hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, createdAt: 7);
    expect(HomestayBooking.fromMap('hb1', hb.toMap()).createdAt, 7);
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(HomestayBooking(guestId: 'me', hostId: 'h1', homeName: 'H',
        hostName: 'M', petId: 'x', petName: 'B', ratePerNight: 900, checkIn: DateTime(2026, 7, 20),
        checkOut: DateTime(2026, 7, 23), nights: 3, subtotal: 2700, fee: 150, total: 2850));
    expect((await repo.watchMyHomestayBookings('me').first).single.createdAt, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/booking_createdat_test.dart`
Expected: FAIL — `createdAt` is not a parameter/field.

- [ ] **Step 3: Add `createdAt` to the two models**

In `lib/data/models/booking.dart`: add `createdAt` to the field list, constructor, `toMap`, `fromMap`:
```dart
  final int rate, fee, total, createdAt;
```
(change the existing `final int rate, fee, total;` line to include `createdAt`), constructor add `this.createdAt = 0,` (after `this.status = 'confirmed',`), `toMap` add `'createdAt': createdAt,`, and in `fromMap` add:
```dart
        createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0, // stale serverTimestamp -> 0
```
Do the identical change in `lib/data/models/homestay_booking.dart`: add `createdAt` to the `final int ratePerNight, nights, subtotal, fee, total;` line (→ `..., total, createdAt;`), constructor `this.createdAt = 0,` (after `this.status = 'requested',`), `toMap` `'createdAt': createdAt,`, `fromMap` `createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0,`.

- [ ] **Step 4: Stamp `createdAt` (client int) in the Firestore create methods**

In `lib/data/repositories/firebase/firestore_booking_repository.dart`, replace `createBooking`:
```dart
  @override
  Future<void> createBooking(Booking booking) {
    final map = booking.toMap();
    if ((map['createdAt'] ?? 0) == 0) map['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    return _col.add(map);
  }
```
In `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`, replace `createHomestayBooking`:
```dart
  @override
  Future<void> createHomestayBooking(HomestayBooking booking) {
    final map = booking.toMap();
    if ((map['createdAt'] ?? 0) == 0) map['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    return _col.add(map);
  }
```
(Both previously wrote `'createdAt': FieldValue.serverTimestamp()`, which was never read back — this switches to a client int for feed ordering. `FieldValue` may now be an unused import; remove it if analyze flags it, keeping the `cloud_firestore` import for the rest.)

- [ ] **Step 5: Stamp in the in-memory fakes**

In `test/support/fakes.dart`, `InMemoryBookingRepository.createBooking`:
```dart
  @override
  Future<void> createBooking(Booking booking) async {
    final stamped = booking.createdAt != 0 ? booking
        : Booking.fromMap(booking.id, {...booking.toMap(), 'createdAt': DateTime.now().millisecondsSinceEpoch});
    _bookings.add(stamped);
    _controller.add(List.of(_bookings));
  }
```
`InMemoryHomestayBookingRepository.createHomestayBooking`:
```dart
  @override
  Future<void> createHomestayBooking(HomestayBooking booking) async {
    final stamped = booking.createdAt != 0 ? booking
        : HomestayBooking.fromMap(booking.id, {...booking.toMap(), 'createdAt': DateTime.now().millisecondsSinceEpoch});
    _bookings.add(stamped);
    _controller.add(List.of(_bookings));
  }
```

- [ ] **Step 6: Run tests + full suite**

Run: `flutter test test/data/booking_createdat_test.dart` → PASS. Then `flutter test` (whole suite — the model change is additive; existing tests stay green) and `flutter analyze`.

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/booking.dart lib/data/models/homestay_booking.dart lib/data/repositories/firebase/firestore_booking_repository.dart lib/data/repositories/firebase/firestore_homestay_booking_repository.dart test/support/fakes.dart test/data/booking_createdat_test.dart
git commit -m "feat: add client-int createdAt to Booking + HomestayBooking (feed ordering)"
```

---

### Task 2: `notifsSeenAt` on `UserProfile` + `markNotificationsSeen`

**Files:**
- Modify: `lib/data/models/user_profile.dart`
- Modify: `lib/data/repositories/user_repository.dart`, `lib/data/repositories/firebase/firestore_user_repository.dart`
- Modify: `test/support/fakes.dart` (`InMemoryUserRepository`)
- Test: `test/data/notifs_seen_test.dart`

**Interfaces:**
- Produces: `UserProfile.notifsSeenAt` (int, default 0) + `copyWith({String? area, int? notifsSeenAt})`; `UserRepository.markNotificationsSeen(String uid)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/notifs_seen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import '../support/fakes.dart';

void main() {
  test('UserProfile.notifsSeenAt round-trips', () {
    const u = UserProfile(uid: 'me', name: 'Radhika', email: 'r@x.com', area: 'Bandra',
        role: Role.petParent, notifsSeenAt: 99);
    expect(UserProfile.fromMap('me', u.toMap()).notifsSeenAt, 99);
    expect(const UserProfile(uid: 'me', name: 'R', email: 'e', area: 'a', role: Role.petParent).notifsSeenAt, 0);
  });

  test('markNotificationsSeen sets notifsSeenAt + re-emits', () async {
    final repo = InMemoryUserRepository();
    await repo.createUser(const UserProfile(uid: 'me', name: 'R', email: 'e', area: 'a', role: Role.petParent));
    expect((await repo.watchUser('me').first)!.notifsSeenAt, 0);
    await repo.markNotificationsSeen('me');
    expect((await repo.watchUser('me').first)!.notifsSeenAt, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/notifs_seen_test.dart`
Expected: FAIL — `notifsSeenAt` / `markNotificationsSeen` not defined.

- [ ] **Step 3: Add `notifsSeenAt` to `UserProfile`**

In `lib/data/models/user_profile.dart`:
```dart
  final String uid, name, email, area;
  final Role role;
  final int notifsSeenAt;

  const UserProfile({
    required this.uid, required this.name, required this.email,
    required this.area, required this.role, this.notifsSeenAt = 0,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'area': area,
        'role': role.storageKey,
        'notifsSeenAt': notifsSeenAt,
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        role: Role.fromStorage((m['role'] ?? 'petParent') as String),
        notifsSeenAt: (m['notifsSeenAt'] ?? 0) as int,
      );

  UserProfile copyWith({String? area, int? notifsSeenAt}) => UserProfile(
        uid: uid, name: name, email: email, area: area ?? this.area, role: role,
        notifsSeenAt: notifsSeenAt ?? this.notifsSeenAt,
      );
```

- [ ] **Step 4: Add `markNotificationsSeen` to the interface + impls**

In `lib/data/repositories/user_repository.dart`, add to the interface:
```dart
  Future<void> markNotificationsSeen(String uid);
```
In `lib/data/repositories/firebase/firestore_user_repository.dart`, add:
```dart
  @override
  Future<void> markNotificationsSeen(String uid) =>
      _col.doc(uid).update({'notifsSeenAt': DateTime.now().millisecondsSinceEpoch});
```
In `test/support/fakes.dart`, `InMemoryUserRepository`, add:
```dart
  @override
  Future<void> markNotificationsSeen(String uid) async {
    final u = _users[uid];
    if (u != null) {
      _users[uid] = u.copyWith(notifsSeenAt: DateTime.now().millisecondsSinceEpoch);
      _ctrl(uid).add(_users[uid]);
    }
  }
```

- [ ] **Step 5: Run test + analyze + commit**

Run: `flutter test test/data/notifs_seen_test.dart` → PASS; `flutter analyze` clean.
```bash
git add lib/data/models/user_profile.dart lib/data/repositories/user_repository.dart lib/data/repositories/firebase/firestore_user_repository.dart test/support/fakes.dart test/data/notifs_seen_test.dart
git commit -m "feat: add UserProfile.notifsSeenAt + markNotificationsSeen (notifications seen cursor)"
```

---

### Task 3: `NotificationItem` + `buildNotifications` (pure feed builder)

**Files:**
- Create: `lib/features/notifications/notification_item.dart`
- Test: `test/features/notifications_builder_test.dart`

**Interfaces:**
- Consumes: `Chat` (`hasUnread`, `otherName`, `lastMessage`, `lastMessageAt`, `id`), `Review` (`authorName`, `stars`, `text`, `createdAt`), `Booking` (`proName`, `serviceType.label`, `dateLabel`, `createdAt`), `HomestayBooking` (`petName`, `homeName`, `nights`, `createdAt`), `Pro`, `Homestay`, `Routes` (`chat`, `servicePro`, `host`, `bookings`).
- Produces: `enum PgNotificationType { message, review, booking, homestay }`; `class NotificationItem`; `List<NotificationItem> buildNotifications({required String myUid, required int seenAt, required List<Chat> chats, required List<Review> reviews, required List<Booking> bookings, required List<HomestayBooking> homestays, Pro? myPro, Homestay? myHomestay})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/chat.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/features/notifications/notification_item.dart';

void main() {
  test('buildNotifications maps sources, sorts newest-first, flags read + deep-links', () {
    const chat = Chat(id: 'c1', participants: ['me', 'a'], names: {'me': 'Me', 'a': 'Aarav'},
        lastMessage: 'hi there', lastSenderId: 'a', lastMessageAt: 300, lastRead: {'me': 0});
    const review = Review(targetType: ReviewTargetType.pro, targetId: 'me', targetName: 'Me',
        authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 5, text: 'great', createdAt: 200);
    const booking = Booking(id: 'bk1', parentId: 'me', proId: 'p', proName: 'Aarav', petId: 'x',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', createdAt: 100);

    final items = buildNotifications(myUid: 'me', seenAt: 150, chats: const [chat],
        reviews: const [review], bookings: const [booking], homestays: const []);

    expect(items.map((i) => i.type).toList(),
        [PgNotificationType.message, PgNotificationType.review, PgNotificationType.booking]); // 300,200,100
    expect(items[0].title, 'New message from Aarav');
    expect(items[0].route, Routes.chat);
    expect(items[0].read, isFalse);            // 300 > 150
    expect(items[1].route, isNull);            // review, no myPro/myHomestay -> no deep-link
    expect(items.last.read, isTrue);           // booking 100 <= 150
    expect(items.last.route, Routes.bookings);
  });

  test('review deep-links to my Pro profile when I have one; a read chat is excluded', () {
    const chatRead = Chat(id: 'c1', participants: ['me', 'a'], names: {'me': 'Me', 'a': 'A'},
        lastMessage: 'hi', lastSenderId: 'a', lastMessageAt: 100, lastRead: {'me': 500}); // read
    const review = Review(targetType: ReviewTargetType.pro, targetId: 'me', targetName: 'Me',
        authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 4, text: '', createdAt: 200);
    const pro = Pro(uid: 'me', name: 'Me', area: 'Bandra', bio: 'b', serviceType: ServiceType.walker,
        rate: 250, experienceYears: 3);

    final items = buildNotifications(myUid: 'me', seenAt: 0, chats: const [chatRead],
        reviews: const [review], bookings: const [], homestays: const [], myPro: pro);
    expect(items.length, 1);                    // read chat excluded
    expect(items.single.type, PgNotificationType.review);
    expect(items.single.route, Routes.servicePro);
    expect(items.single.extra, pro);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notifications_builder_test.dart`
Expected: FAIL — `NotificationItem` / `buildNotifications` not found.

- [ ] **Step 3: Implement `lib/features/notifications/notification_item.dart`**

```dart
import 'package:flutter/material.dart';
import '../../core/router/routes.dart';
import '../../data/models/booking.dart';
import '../../data/models/chat.dart';
import '../../data/models/homestay.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/pro.dart';
import '../../data/models/review.dart';

enum PgNotificationType { message, review, booking, homestay }

class NotificationItem {
  final PgNotificationType type;
  final String icon; // emoji
  final Color accent;
  final String title, body;
  final int timestamp; // millis — sort + unread
  final String? route; // deep-link target (null = non-navigating)
  final Object? extra;
  final bool read;

  const NotificationItem({
    required this.type, required this.icon, required this.accent,
    required this.title, required this.body, required this.timestamp,
    this.route, this.extra, this.read = false,
  });
}

/// Builds the derived notification feed (newest first) from the user's own data.
List<NotificationItem> buildNotifications({
  required String myUid,
  required int seenAt,
  required List<Chat> chats,
  required List<Review> reviews,
  required List<Booking> bookings,
  required List<HomestayBooking> homestays,
  Pro? myPro,
  Homestay? myHomestay,
}) {
  bool unread(int ts) => ts > seenAt;
  final items = <NotificationItem>[];

  for (final c in chats) {
    if (!c.hasUnread(myUid)) continue;
    items.add(NotificationItem(
      type: PgNotificationType.message, icon: '💬', accent: const Color(0xFF6B8DE0),
      title: 'New message from ${c.otherName(myUid)}', body: c.lastMessage,
      timestamp: c.lastMessageAt, route: Routes.chat, extra: c, read: !unread(c.lastMessageAt)));
  }

  final (String? reviewRoute, Object? reviewExtra) = myPro != null
      ? (Routes.servicePro, myPro)
      : myHomestay != null
          ? (Routes.host, myHomestay)
          : (null, null);
  for (final r in reviews) {
    final stars = List.filled(r.stars.clamp(0, 5), '★').join();
    items.add(NotificationItem(
      type: PgNotificationType.review, icon: '⭐', accent: const Color(0xFFF59E2E),
      title: 'New review from ${r.authorName}',
      body: r.text.isEmpty ? stars : '$stars  ${r.text}',
      timestamp: r.createdAt, route: reviewRoute, extra: reviewExtra, read: !unread(r.createdAt)));
  }

  for (final b in bookings) {
    items.add(NotificationItem(
      type: PgNotificationType.booking, icon: '✅', accent: const Color(0xFF34B27B),
      title: 'Booking confirmed with ${b.proName}',
      body: '${b.serviceType.label} · ${b.dateLabel}',
      timestamp: b.createdAt, route: Routes.bookings, read: !unread(b.createdAt)));
  }

  for (final s in homestays) {
    items.add(NotificationItem(
      type: PgNotificationType.homestay, icon: '🏡', accent: const Color(0xFFF97316),
      title: 'Homestay request · ${s.petName}',
      body: '${s.homeName} · ${s.nights} nights',
      timestamp: s.createdAt, route: Routes.bookings, read: !unread(s.createdAt)));
  }

  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notifications_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/features/notifications/notification_item.dart test/features/notifications_builder_test.dart
git commit -m "feat: add NotificationItem + buildNotifications (derived feed builder)"
```

---

### Task 4: Providers — `notificationsProvider` + `hasUnreadNotificationsProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/notifications_provider_test.dart`

**Interfaces:**
- Consumes: `buildNotifications`, `NotificationItem` (Task 3); existing `authRepositoryProvider`, `currentUserProfileProvider`, `myChatsProvider`, `reviewsProvider`, `myBookingsProvider`, `myHomestayBookingsProvider`, `currentProProvider`, `currentHomestayProvider`.
- Produces: `notificationsProvider` → `Provider<List<NotificationItem>>`; `hasUnreadNotificationsProvider` → `Provider<bool>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/notifications_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('notificationsProvider surfaces a review; Mark all read clears unread', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: uid,
        targetName: 'Radhika', authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 5,
        text: 'great', createdAt: DateTime.now().millisecondsSinceEpoch));

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(notificationsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    expect(container.read(notificationsProvider).length, 1);
    expect(container.read(hasUnreadNotificationsProvider), isTrue);

    await users.markNotificationsSeen(uid);
    await pumpEventQueue();
    expect(container.read(hasUnreadNotificationsProvider), isFalse); // seenAt now >= review time
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/notifications_provider_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add imports (near the other imports): `import '../../features/notifications/notification_item.dart';`, `import '../models/homestay.dart';` (if not already present — it is), and ensure `chat.dart`, `booking.dart`, `homestay_booking.dart`, `review.dart`, `pro.dart` are imported (all already are except confirm `review.dart` from 7c and `homestay_booking.dart` from 7c — both present). Then append:

```dart
final notificationsProvider = Provider<List<NotificationItem>>((ref) {
  final uid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
  final seenAt = ref.watch(currentUserProfileProvider).value?.notifsSeenAt ?? 0;
  return buildNotifications(
    myUid: uid,
    seenAt: seenAt,
    chats: ref.watch(myChatsProvider).value ?? const [],
    reviews: ref.watch(reviewsProvider(uid)).value ?? const [],
    bookings: ref.watch(myBookingsProvider).value ?? const [],
    homestays: ref.watch(myHomestayBookingsProvider).value ?? const [],
    myPro: ref.watch(currentProProvider).value,
    myHomestay: ref.watch(currentHomestayProvider).value,
  );
});

final hasUnreadNotificationsProvider =
    Provider<bool>((ref) => ref.watch(notificationsProvider).any((n) => !n.read));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/notifications_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze
git add lib/data/repositories/providers.dart test/data/notifications_provider_test.dart
git commit -m "feat: add notificationsProvider + hasUnreadNotificationsProvider (derived feed)"
```

---

### Task 5: `NotificationsScreen` + `/notifications` route

**Files:**
- Create: `lib/features/notifications/notifications_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `notifications`)
- Modify: `lib/core/router/app_router.dart` (import + protect + route)
- Test: `test/features/notifications_screen_test.dart`

**Interfaces:**
- Consumes: `notificationsProvider`, `hasUnreadNotificationsProvider`, `NotificationItem`, `authRepositoryProvider`, `userRepositoryProvider` (`markNotificationsSeen`), `Post.timeAgo`, `PgAppBar`, `Routes`.
- Produces: `NotificationsScreen`; `Routes.notifications == '/notifications'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders notifications; Mark all read clears the list state', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: uid,
        targetName: 'Radhika', authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 5,
        text: 'So gentle with Bruno', createdAt: DateTime.now().millisecondsSinceEpoch));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(reviews),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.notifications);
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('New review from Karan'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    // Cursor advanced -> nothing unread -> the Mark all read action is gone.
    expect(find.text('Mark all read'), findsNothing);
    expect(find.text('New review from Karan'), findsOneWidget); // item still listed, now read
  });

  testWidgets('empty state when there are no notifications', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.notifications);
    await tester.pumpAndSettle();

    expect(find.textContaining('all caught up'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notifications_screen_test.dart`
Expected: FAIL — `NotificationsScreen` / route not found.

- [ ] **Step 3: Add the route constant**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `rate`):
```dart
  static const notifications = '/notifications';
```

- [ ] **Step 4: Implement `lib/features/notifications/notifications_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';
import 'notification_item.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final items = ref.watch(notificationsProvider);
    final hasUnread = ref.watch(hasUnreadNotificationsProvider);
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.chevron_left, color: c.text))),
              const SizedBox(width: 14),
              Expanded(child: Text('Notifications',
                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
              if (hasUnread)
                GestureDetector(
                  onTap: () => ref.read(userRepositoryProvider).markNotificationsSeen(myUid),
                  child: Text('Mark all read', style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
            ]),
          ),
          Expanded(child: items.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text("You're all caught up — no notifications yet.",
                  textAlign: TextAlign.center, style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: [for (final n in items) _NotifRow(item: n)],
              )),
        ]),
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final NotificationItem item;
  const _NotifRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.route == null ? null : () => context.push(item.route!, extra: item.extra),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: item.read ? c.surface : c.brandSoft,
          border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13)),
            child: Text(item.icon, style: const TextStyle(fontSize: 19))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: PgText.poppins(14, FontWeight.w700, color: c.text)),
            const SizedBox(height: 3),
            Text(item.body, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Post.timeAgo(item.timestamp), style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            if (!item.read) ...[
              const SizedBox(height: 6),
              Container(width: 8, height: 8,
                decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle)),
            ],
          ]),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the route + protect it in `app_router.dart`**

Add `import '../../features/notifications/notifications_screen.dart';`; add `Routes.notifications` to the `_protected` set; add this route (after the `Routes.chatList` route):
```dart
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/notifications_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/notifications/notifications_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/notifications_screen_test.dart
git commit -m "feat: add Notifications screen (derived feed + mark all read) + /notifications route"
```

---

### Task 6: Home header bell + unread dot

**Files:**
- Modify: `lib/features/home/home_screen.dart` (add a 🔔 bell before the messages icon)
- Test: `test/features/home_bell_test.dart`

**Interfaces:**
- Consumes: `hasUnreadNotificationsProvider`, `Routes.notifications`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home_bell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Home bell opens Notifications and shows an unread dot that clears', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: uid,
        targetName: 'Radhika', authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 5,
        text: 'great', createdAt: DateTime.now().millisecondsSinceEpoch));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(reviews),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notif-dot')), findsOneWidget); // unread review
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home_bell_test.dart`
Expected: FAIL — no bell icon / no dot.

- [ ] **Step 3: Add the bell to the Home header**

In `lib/features/home/home_screen.dart`, the header row currently has the messages `GestureDetector` (a `Container` with `Icons.chat_bubble_outline_rounded`) immediately before `const PgImageSlot(size: 46, circle: true)`. Insert the bell **before** that messages `GestureDetector`:
```dart
              GestureDetector(
                onTap: () => context.push(Routes.notifications),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13)),
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    Icon(Icons.notifications_none_rounded, size: 20, color: c.text),
                    if (ref.watch(hasUnreadNotificationsProvider))
                      Positioned(top: -2, right: -2, child: Container(
                        key: const ValueKey('notif-dot'), width: 9, height: 9,
                        decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle,
                          border: Border.all(color: c.surface2, width: 1.5)))),
                  ])),
              ),
```
(`ref` is already available — `HomeScreen` is a `ConsumerWidget`. `Routes` and `context.push` are already imported.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/home_bell_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/home/home_screen.dart test/features/home_bell_test.dart
git commit -m "feat: add a notifications bell (unread dot) to the Home header"
```
Expected: whole suite green, analyze clean.

---

### Task 7: Emulator `createdAt` assertion + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (assert `createdAt` round-trips on a real booking)

- [ ] **Step 1: Extend the bookings integration test**

In `integration_test/firebase_repos_test.dart`, find the existing `testWidgets('bookings create + watchMyBookings round-trip ...')` and add, after its existing `expect(mine.single.total, 275);` line:
```dart
    expect(mine.single.createdAt, greaterThan(0)); // client-int createdAt stamped on create
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

Run: `flutter run -d emulator-5554`. Trigger activity (get a message / book a service / receive a review), open Home → the 🔔 shows a dot; tap it → the Notifications feed lists the events newest-first; tap an item → it deep-links (message → the conversation); tap **Mark all read** → the dot clears.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: assert booking createdAt round-trips against the Firestore emulator"
```

---

## Self-Review

**Spec coverage:**
- Derived feed, four sources, newest-first, read via `notifsSeenAt` → Tasks 3–4. ✓
- `createdAt` on Booking/HomestayBooking (additive, client int, stamped on create) → Task 1. ✓
- `UserProfile.notifsSeenAt` + `markNotificationsSeen` → Task 2. ✓
- NotificationsScreen + `/notifications` + Mark all read + deep-links + empty state → Task 5. ✓
- Home bell + unread dot → Task 6. ✓
- No new collection/rules; emulator `createdAt` assertion → Task 7. ✓
- Deferred (reciprocal-woof, post-replies, nearby, FCM) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. Timestamps are client ints; `fromMap` guards `createdAt` against a stale `Timestamp` (`is int`). `List.filled(...).join()` used for stars (Dart has no `String*int`).

**Type consistency:**
- `Booking.createdAt`/`HomestayBooking.createdAt` (int) defined Task 1, consumed Task 3 (builder) + Task 7 (assertion). ✓
- `UserProfile.notifsSeenAt` + `copyWith(notifsSeenAt:)` + `markNotificationsSeen` defined Task 2, consumed Task 4 (`notifsSeenAt`) + Task 5 (`markNotificationsSeen`). ✓
- `NotificationItem` (`type, icon, accent, title, body, timestamp, route, extra, read`) + `PgNotificationType` + `buildNotifications({myUid, seenAt, chats, reviews, bookings, homestays, myPro, myHomestay})` defined Task 3, consumed Task 4 (provider) + Tasks 5–6 (screen/bell via providers). ✓
- `notificationsProvider`/`hasUnreadNotificationsProvider` defined Task 4, consumed Tasks 5 (screen) + 6 (bell). ✓
- `Routes.notifications` added Task 5, consumed Tasks 5 (route + `_protected`) + 6 (bell push). ✓
- Reused existing APIs verified: `Chat.hasUnread/otherName/lastMessage/lastMessageAt`, `Review.authorName/stars/text/createdAt`, `Booking.proName/serviceType.label/dateLabel`, `HomestayBooking.petName/homeName/nights`, `Pro`/`Homestay`, `currentUserProfileProvider`/`currentProProvider`/`currentHomestayProvider`/`myChatsProvider`/`reviewsProvider`/`myBookingsProvider`/`myHomestayBookingsProvider`, `Post.timeAgo(int)`, `PgAppBar`, the Home messages-icon block, and `withValues(alpha:)` (current Flutter Color API). ✓
