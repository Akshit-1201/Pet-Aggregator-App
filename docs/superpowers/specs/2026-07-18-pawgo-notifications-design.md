# Pawgo Slice 7d: Notifications — Design

> **Status:** approved design (2026-07-18). Last of four sub-slices of Phase 7 (cross-cutting). Built on the live Firebase backend — **no mock data**. An in-app notification feed **derived** from the user's existing data — no new collection, no cross-user writes, no rules change.

## Goal

Give the user a **Notifications** feed reached from a 🔔 bell on the Home header (beside the 💬 messages icon), with an **unread dot**. The feed is **derived** by merging four streams the user can already read — unread chats, reviews they received, their service bookings, and their homestay requests — into one time-sorted list. Unread is tracked by a single per-user "seen" cursor; **Mark all read** clears it. Tapping a notification deep-links to the relevant screen.

Screens match `design/Pawgo Prototype.dc.html` (Notifications 884–901; Home-header bell line 384).

## Design decisions (settled during brainstorming)

- **Derived feed, not a stored log.** No `notifications` collection, no actor-writes, no cross-user create rule, no Cloud Function. The feed is computed client-side from existing per-user reads. (The stored-log alternative was rejected as heavier and touching 5–6 shipped features.)
- **Four sources** (all already readable under current rules): unread **chats** (`myChatsProvider`, `hasUnread`), **reviews received** (`reviewsProvider(myUid)` — `targetId == me`), **my service bookings** (`myBookingsProvider`), **my homestay requests** (`myHomestayBookingsProvider`).
- **Ordering needs timestamps** → add an additive `createdAt` (client millis) to `Booking` and `HomestayBooking`, **stamped centrally in the repository `create*` methods** (so every created booking is stamped regardless of caller). Old docs default to `0` and sort last. Chats use `lastMessageAt`, reviews use `createdAt` (both already exist).
- **Unread = a single "seen" cursor** `UserProfile.notifsSeenAt` (int millis). An item is unread when its `timestamp > notifsSeenAt`; the bell dot shows if any item is unread. **Mark all read** sets `notifsSeenAt = now`. Opening the screen does **not** auto-clear (matches the prototype's explicit button).
- **Deep-links:** message → the conversation (`/chat`, Chat via extra); my booking / homestay request → **My Bookings** (`/bookings`); review received → my own **Pro/Host profile** (via `currentProProvider`/`currentHomestayProvider`).
- **No new Firestore rules** — every source is already readable by the owner; `notifsSeenAt` lives on the user's own doc (existing `users` owner-write rule covers it).
- **Deferred:** reciprocal-woof-match and post-reply notifications (need swipe cross-referencing / a `collectionGroup` query), "nearby pet" (needs maps/presence), and **FCM push** (its own later phase). This slice is the in-app feed only.

## Scope

**In scope**
- `Booking.createdAt` + `HomestayBooking.createdAt` (additive), stamped in the `create*` repo methods (Firestore + fakes).
- `UserProfile.notifsSeenAt` + `UserRepository.markNotificationsSeen(uid)` (+ Firestore impl + fake).
- A `NotificationItem` view-model + a builder mapping each source → items; `notificationsProvider` (merged, sorted, read-flagged) + `hasUnreadNotificationsProvider`.
- **NotificationsScreen** + `/notifications` route; a 🔔 bell on the Home header with an unread dot.
- TDD with in-memory fakes; a `createdAt` round-trip assertion added to the existing bookings emulator test.

**Out of scope (later)**
- A stored notifications collection / server-generated notifications / Cloud Functions.
- Reciprocal-woof-match, post-reply, and "nearby pet" notifications.
- FCM push notifications (separate later phase).
- Per-notification read state, swipe-to-dismiss, notification settings/preferences.

## Data-model & repository changes

```
// additive, backward-compatible (old docs → 0)
bookings/{id}          .createdAt : int millis   (stamped in createBooking)
homestayBookings/{id}  .createdAt : int millis   (stamped in createHomestayBooking)
users/{uid}            .notifsSeenAt : int millis (owner-written; existing users rule)
```

- `Booking` / `HomestayBooking`: add `final int createdAt;` (default `0`) to the constructor + `toMap`/`fromMap` (`fromMap` defaults `0`). The Firestore `createBooking`/`createHomestayBooking` and the in-memory fakes write `{...toMap(), 'createdAt': now}` at create time.
- `UserProfile`: add `final int notifsSeenAt;` (default `0`) to the constructor + `toMap`/`fromMap`; extend `copyWith`.
- `UserRepository`: add `Future<void> markNotificationsSeen(String uid)` → Firestore `users/{uid}.update({'notifsSeenAt': now})`; fake sets the field on the stored profile and re-emits.

## The derived feed (`features/notifications/`)

`NotificationItem` — pure view-model (not persisted):
```dart
enum PgNotificationType { message, review, booking, homestay }
class NotificationItem {
  final PgNotificationType type;
  final String icon;            // emoji
  final Color accent;
  final String title, body;
  final int timestamp;          // millis, for sort + unread
  final String? route;          // deep-link target (null = no-op tap)
  final Object? extra;          // e.g. the Chat for /chat
  final bool read;
}
```

- `notificationsProvider` → `Provider<List<NotificationItem>>` that `ref.watch`es the four sources (`.value ?? const []`) + `currentUserProfileProvider` (for `notifsSeenAt`) and builds:
  - **message:** for each `chat` in `myChats` where `chat.hasUnread(myUid)` → `💬` "New message from {otherName}", body `lastMessage`, `timestamp = lastMessageAt`, route `/chat`, extra `chat`.
  - **review:** for each `review` in `reviewsProvider(myUid)` → `⭐` "New review from {authorName}", body "{★×stars} {text}", `timestamp = createdAt`, route → my Pro/Host profile (see deep-links).
  - **booking:** for each `b` in `myBookings` → `✅` "Booking confirmed with {proName}", body "{serviceType.label} · {dateLabel}", `timestamp = createdAt`, route `/bookings`.
  - **homestay:** for each `s` in `myHomestayBookings` → `🏡` "Homestay request · {petName}", body "{homeName} · {nights} nights", `timestamp = createdAt`, route `/bookings`.
  - Sort by `timestamp` desc; set `read = timestamp <= notifsSeenAt`.
- `hasUnreadNotificationsProvider` → `Provider<bool>` = `notificationsProvider.any((n) => !n.read)`.
- The review deep-link uses `currentProProvider.value` (→ `/service-pro`, extra that Pro) if present, else `currentHomestayProvider.value` (→ `/host`, extra that Homestay), else `null` (no-op tap).

## Screen, entry, routes

1. **NotificationsScreen** (`ConsumerWidget`, route `/notifications`, protected) — `PgAppBar`-style header "Notifications" + a **Mark all read** action (→ `userRepository.markNotificationsSeen(myUid)`; only shown when something is unread). The list renders each `NotificationItem`: a rounded accent-tinted icon tile, title, body, `Post.timeAgo(timestamp)`, and — when `!read` — a small trailing brand dot plus a subtly brand-tinted row surface (read rows use the plain surface). Empty state ("You're all caught up — no notifications yet."). Row tap: if `route != null`, `context.push(route, extra: extra)`.
2. **Home header bell** (`home_screen.dart`) — a 🔔 icon **before** the 💬 messages icon → `context.push(Routes.notifications)`, with a small unread dot overlaid when `hasUnreadNotificationsProvider` is true (mirrors the messages-icon tile styling).
3. **Route:** `notifications = '/notifications'` (top-level **protected**).

## Error handling

The four sources are `AsyncValue`s; the builder uses `.value ?? const []`, so loading/error states simply contribute nothing (the feed shows what's available) — consistent with the codebase idiom. `markNotificationsSeen` is fire-and-forget from the button; a failure leaves the dot set (no data loss).

## Testing

TDD with in-memory fakes via `pumpPgApp` overrides:
- `Booking`/`HomestayBooking` `createdAt` round-trip; the fakes stamp `createdAt` on create (so `watchMyBookings` items carry a non-zero `createdAt`).
- `UserProfile` `notifsSeenAt` round-trip; `InMemoryUserRepository.markNotificationsSeen` sets it + re-emits via `watchUser`.
- Notification builder: each source maps to the right item (icon/title/body/timestamp/route); merged list is newest-first; `read` is `timestamp <= notifsSeenAt`; `hasUnreadNotificationsProvider` reflects unread items.
- **NotificationsScreen**: renders items from multiple sources; empty state; **Mark all read** flips everything to read (dot clears); a message row tap opens the conversation.
- **Home bell**: navigates to `/notifications`; the unread dot shows when an unread item exists and is gone after Mark all read.
- Extend `integration_test/firebase_repos_test.dart`: assert a created booking's `createdAt > 0` round-trips through Firestore (the emulator already covers the underlying reads; no new collection/rules to verify).

## Prerequisites

None new — Firestore + Email/Password are live; all four source collections already exist and are readable by the owner. No rules deploy needed.

## Deliverable / definition of done

A 🔔 bell on Home shows an unread dot when the user has recent activity; tapping it opens a Notifications feed merging unread messages, reviews received, and booking/homestay activity, newest first; tapping an item deep-links to the right screen; **Mark all read** clears the dot. `flutter analyze` clean, `flutter test` green (fakes), the emulator integration suite still passes (with the added `createdAt` assertion), debug APK builds.
