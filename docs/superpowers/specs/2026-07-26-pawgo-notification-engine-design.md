# Pawgo Slice 21: Notification scenarios + engine — Design

> **Status:** approved design (2026-07-26). Defines **every** push Pawgo sends and rebuilds the delivery machinery around that catalogue. Replaces the client-derived notification feed with server-authored records, so push and the in-app feed can no longer disagree. Adds the first time-based notifications the app has ever had.

## The problem this fixes

Push works, but the *system* around it doesn't exist. Three separate problems:

**1. The feed and push are two unrelated implementations.** Six triggers in `functions/src/index.ts` send pushes. Meanwhile `buildNotifications` (`lib/features/notifications/notification_item.dart:32`) re-derives a feed **client-side** from chats, reviews, bookings and stays the user can already read. Nothing connects them. They already disagree — a Woof match pushes but never appears in the feed, and a review notification ships under the *Bookings* toggle. `left.md` flags this as "worth unifying eventually".

**2. Roughly a third of what matters is silent.** No notification exists for: a comment on your post, a payment receipt, a processed refund, a released payout, a payout blocked for missing bank details, KYC approved, or KYC rejected. The KYC ones are the sharpest — the admin panel flips `verified` and the partner is never told, so verification looks broken from their side. The receipt is the second sharpest: `RESEND_API_KEY` is still the literal `"unset"`, so email receipts deploy but never send. **A paying user currently receives no confirmation through any channel.**

**3. Nothing is time-based.** There is no scheduler. An accepted stay that the guest forgets to pay for silently expires, and nobody is nudged. A pro is never reminded of tomorrow's appointment. Nobody is ever asked for a review, which is why `reviewCount` stays near zero and the ratings the marketplace runs on never accumulate.

## Design decisions (settled during brainstorming)

- **Scope is transactional + lifecycle. No marketing.** Every notification is something the recipient must act on or has money riding on. Growth pushes ("new pets near you", dormant win-backs) are explicitly out — they are what gets notification permission revoked, and they'd drag in frequency caps and an unsubscribe story.
- **Scheduled reminders go out in one 09:00 IST batch.** Not "whenever due" — that wakes people at 3am. Not a quiet-hours held-queue — that's a second moving part for no gain when every reminder is day-granular anyway. Event-driven pushes stay instant.
- **Seven categories: five user-controlled, two essential.** Messages, Bookings, Woofs, Community, Reminders are toggleable. Money and Account (refund processed, payout paid, KYC verdict) **ignore preferences**, because silently failing to tell someone their refund landed or their ID was rejected is a support incident, not a preference. Settings states this rather than hiding it.
- **The notification record is written before the preference check, and regardless of it.** Muting a category opts you out of *interruption*, not *information*. Your booking history must not vanish from the feed because you turned off push. This is also what makes the feed trustworthy as a record.
- **Rendered text is stored, not re-rendered on the client.** Storing params and templating client-side would put the same 22 templates in two places in two languages — precisely the drift being removed. The server catalogue is the single source of copy. English-only, Mumbai market, so nothing is lost.
- **Presentation stays on the client.** The doc stores `scenario`, `category`, `title`, `body`, `route`, `createdAt`, `read`. Emoji and accent colour are a client-side lookup keyed by category; storing `0xFF34B27B` in Firestore would be a category error.
- **Notifications are extracted out of `index.ts`.** That file is already 906 lines carrying payments, refunds, payouts, deletion and masking. Adding 12 scenarios plus a scheduler in place would make it unmaintainable.
- **Now is the only free moment for the migration.** Replacing the derived feed means every user's feed starts empty. The database holds 4 users, 2 pets and 2 posts from the QA run and **no build has shipped**, so nobody is affected. That window closes at internal testing.
- **Deferred:** notification grouping/summary ("3 new messages" as one OS notification), rich media in pushes, in-app notification badges per tab, digest emails, per-scenario (rather than per-category) preferences.

## Scope

**In scope**

- New `functions/src/notify/` module: `catalog.ts`, `notify.ts`, `triggers.ts`, `reminders.ts`.
- `sendPushTo` and the six existing push triggers **move out of** `index.ts` into that module; `index.ts` calls `notify()` where it currently inlines pushes.
- 12 new scenarios (1 community, 4 money, 2 account, 5 reminders).
- New scheduled Function `dailyNotifications` (09:00 IST) covering five reminder types plus the retention sweep.
- New Firestore collection `notifications/{uid}/items/{key}` + rules + indexes.
- Client: `NotificationRepository` interface + Firestore implementation; `buildNotifications` **deleted**; feed reads the stream; per-item `read` replaces the global `notifsSeenAt`.
- Settings: two new toggles (Community, Reminders) + an "Always on" treatment for the essential tier.
- `vitest` added to `functions/` (no test runner exists there today).
- Rewrites of the four existing Dart tests that target the deleted builder.

**Out of scope**

- No change to `PushService`, token storage, or token rotation — that layer works. `PushRegistrar._handleTap` only gains any new routes in its allowlist.
- No change to payments, refunds, payout mechanics, or moderation, beyond calling `notify()` at points that are currently silent.
- No new UI screens. The Notifications screen changes its data source, not its layout.
- No backfill of notifications for events that already happened.

---

## The scenario catalogue

22 scenarios. 10 exist today, 12 are new.

### Event-driven — fire immediately

| ID | Scenario | Recipient | Category | Source | Status |
|---|---|---|---|---|---|
| M1 | New chat message | Other participant; suppressed if they blocked the sender | messages | `chats/{id}/messages` create | exists |
| B1 | Service booking paid | Pro | bookings | `bookings` → `confirmed` | exists |
| B2 | Service booking cancelled | Pro | bookings | `bookings` → `cancelled` | exists |
| B3 | Stay request created | Host | bookings | `homestayBookings` create | exists |
| B4 | Stay request accepted | Guest | bookings | → `accepted` | exists |
| B5 | Stay request declined | Guest | bookings | → `declined` | exists |
| B6 | Stay paid & confirmed | Host | bookings | → `paid` | exists |
| B7 | Stay cancelled | Host | bookings | → `cancelled` | exists |
| B8 | Review received | Pro / host | bookings | `reviews` create | exists |
| W1 | Reciprocal woof → match | Both owners | woofs | `swipes` create | exists |
| **C1** | **Comment on your post** | Post author; skipped when commenting on own post | community | `posts/{id}/comments` create | **new** |
| **$1** | **Payment succeeded — receipt** | Payer | money *(essential)* | `verifyBookingPayment` | **new** |
| **$2** | **Refund processed** | Customer | money *(essential)* | `refundBookingPayment` | **new** |
| **$3** | **Payout released** | Pro / host | money *(essential)* | payout → `released` | **new** |
| **$4** | **Payout blocked — add bank details** | Partner | money *(essential)* | nightly sweep — see below | **new** |
| **A1** | **KYC approved — you're verified** | Partner | account *(essential)* | `verificationRequests` → `approved` | **new** |
| **A2** | **KYC rejected + reason** | Partner | account *(essential)* | `verificationRequests` → `rejected` | **new** |

**`$4` is the one exception in this table.** There is no event for *"still has no bank details"* — it is a standing condition, so it is evaluated by the nightly job (`payouts` where `status == 'owed'` and the partner has no linked account) and rate-limited to once a calendar month. It is grouped here because it belongs to the essential money category, not because it is event-driven.

### Scheduled — 09:00 IST daily batch

| ID | Scenario | Condition | Recipient | Category |
|---|---|---|---|---|
| **R1** | Pay today or this booking expires | `bookings`: `status == 'pending'`, `date == today` | Customer | reminders |
| **R2** | Pay to confirm your stay | `homestayBookings`: `status == 'accepted'`, `checkIn == tomorrow` | Guest | reminders |
| **R3** | Appointment tomorrow | `bookings`: `status == 'confirmed'`, `date == tomorrow` | Customer + pro | reminders |
| **R4** | Check-in tomorrow | `homestayBookings`: `status == 'paid'`, `checkIn == tomorrow` | Guest + host | reminders |
| **R5** | How was it? Leave a review | service `confirmed` with `date == yesterday`, or stay `paid` with `checkOut == yesterday`, and no `reviews/{bookingId}` | Customer | reminders |

R2 and R4 are mutually exclusive by status — an accepted-but-unpaid stay gets the payment nudge, a paid one gets the check-in reminder, never both.

### Deliberate omissions

- **A newly created unpaid service booking stays silent for the pro.** They have nothing to act on until money lands. This preserves the existing reasoning in `onServiceBookingWritten`.
- **No reply-to-comment scenario.** `Comment` has no parent field — comments are flat.
- **No moderation-outcome notification.** Telling a reported user they were reported mostly invites retaliation against whoever reported them.

---

## Architecture

```
functions/src/notify/
  catalog.ts    — the 22 scenarios, declared once
  notify.ts     — the single send path (record → pref gate → push → prune)
  triggers.ts   — Firestore triggers: resolve audience + params, call notify()
  reminders.ts  — the 09:00 IST scheduled job + retention sweep
```

A catalogue entry is the entire contract for a scenario:

```ts
{
  id: "stay.checkin.tomorrow",
  category: "reminders",      // → which toggle gates it
  essential: false,           // true = ignores preferences
  collapse: false,            // true = overwrite the existing record
  route: "/bookings",
  render: (p) => ({ title: `${p.petName} checks in tomorrow`,
                    body:  `${p.homeName} · ${p.checkInLabel}` }),
}
```

`notify(scenarioId, uid, params, dedupeKey)` is the **only** way anything sends, in this order:

1. Look up the scenario in the catalogue (unknown id is a compile error, not a runtime one — the catalogue is a typed map).
2. Write `notifications/{uid}/items/{dedupeKey}`.
3. If `essential` is false and the category toggle is off, stop. Absent field means on.
4. Multicast to the user's `fcmTokens`, prune tokens FCM rejects permanently.

### Record shape

`notifications/{uid}/items/{dedupeKey}`:

| Field | Type | Note |
|---|---|---|
| `scenario` | string | catalogue id |
| `category` | string | one of the seven |
| `title`, `body` | string | rendered server-side at send time |
| `route` | string | deep-link target |
| `createdAt` | int millis | sort key; retention key |
| `read` | bool | per-item, replaces the global `notifsSeenAt` |

### Client changes

| Piece | Change |
|---|---|
| `NotificationRepository` | New interface + `FirestoreNotificationRepository`: `watch(uid)`, `markRead(id)`, `markAllRead(uid)` |
| `buildNotifications` | **Deleted** — ~110 lines of client derivation replaced by a stream read |
| `NotificationItem` | Becomes a mapped model; keeps the category → emoji/accent lookup |
| `UserProfile.notifsSeenAt` | Removed — dead once `read` is per-item |
| `NotificationPrefs` | Gains `notifyCommunity`, `notifyReminders`; both default ON when absent |
| Settings | Two new toggles; essential rows render as "Always on" and are not tappable |
| `PushRegistrar` | Unchanged except new routes in the `_handleTap` allowlist |

### Rules

```
match /notifications/{uid}/items/{id} {
  allow read:   if request.auth != null && request.auth.uid == uid;
  allow update: if request.auth != null && request.auth.uid == uid
                && request.resource.data.diff(resource.data).affectedKeys()
                     .hasOnly(['read']);
  allow create, delete: if false;
}
```

Notifications are server-authored records. A client that can create one can forge "your refund was processed"; a client that can delete one can hide a KYC rejection. The Admin SDK bypasses rules, so triggers write freely.

---

## Idempotency

Firestore triggers are **at-least-once** — the payments work already hit a redelivery in production. The doc id **is** the dedupe key, so a redelivery re-writes the same path instead of creating a second record, and the push is skipped when the write was a no-op. No locks required.

| Scenario | Dedupe key | Effect |
|---|---|---|
| M1 chat | `chat_{chatId}` | **collapses** |
| C1 comment | `post_{postId}` | **collapses** |
| B1–B7 | `{scenarioId}_{bookingId}` | once per transition |
| B8 review | `review_{bookingId}` | once |
| W1 match | `match_{otherUid}` | once per pair |
| $1 payment | `payment_{paymentId}` | once |
| $2 refund | `refund_{bookingId}` | once |
| $3 payout released | `payout_{payoutId}` | once |
| $4 payout blocked | `payoutblocked_{YYYY-MM}` | at most monthly |
| A1 / A2 KYC | `kyc_{reviewedAt}` | once per verdict; re-submission allowed |
| R1–R5 | `{R}_{bookingId}` | once, ever |

Keys are scoped per user — records live under `notifications/{uid}/items/`, so R4 sending to both guest and host uses the identical key at two different paths with no collision.

**Collapsing** is the one behaviour that is not plain dedupe. A 40-message conversation must not become 40 feed rows; today's derived feed correctly shows one row per chat. `collapse: true` scenarios overwrite their record in place (new `title`/`body`/`createdAt`, `read` reset to false) while still pushing on every event. **The push is per-event; the feed row is per-thread.** Comments on a busy post get the same treatment.

## Data flow

**Event path:** Firestore write → trigger → resolve recipient + params → `notify()` → record + push.

**Scheduled path:** 09:00 IST cron → five date-equality queries → `notify()` per hit → `$4` sweep → retention sweep.

Both `Booking.date` and `HomestayBooking.checkIn`/`checkOut` serialise as plain `YYYY-MM-DD` strings, so the reminder queries are cheap equality lookups rather than range scans. Each needs a composite index in `firestore.indexes.json`:

- `bookings`: `status` ASC + `date` ASC (serves R1, R3, R5)
- `homestayBookings`: `status` ASC + `checkIn` ASC (serves R2, R4)
- `homestayBookings`: `status` ASC + `checkOut` ASC (serves R5)
- collection group `items`: `createdAt` ASC (serves retention)

**Retention.** The same nightly job deletes records older than 90 days via a collection-group query on `items`. Without it the collection only ever grows; the feed is a rolling window, not an archive.

## Error handling

| Failure | Behaviour |
|---|---|
| Push send throws | Logged, swallowed. The record is already written, so the event still reaches the feed |
| Token rejected (`not-registered` / `invalid`) | Pruned from `fcmTokens` — unchanged from today |
| Recipient doc missing | Skip and log. A deleted account must not crash a trigger |
| One reminder query fails | Wrapped independently — the other four, `$4` and retention still run |
| Record write fails | Logged; push still attempted. Losing the feed row beats losing both |
| Unknown scenario id | Impossible at runtime — typed catalogue map, caught by `tsc` |

`notify()` never throws. A push that fails must not roll back the booking or message that triggered it — this is the existing `sendPushTo` contract and it is preserved.

## Testing

### Server — `vitest` added to `functions/`

New infrastructure, and justified: 22 render functions and IST date arithmetic are exactly where silent bugs live, and there is no runner today.

- Every catalogue entry renders non-empty `title` and `body` from representative params
- Dedupe keys are stable across repeated calls and distinct across scenarios
- `essential: true` scenarios send with the category toggle off; non-essential ones do not
- The record is written even when the preference suppresses the push
- Collapsing scenarios overwrite in place; non-collapsing create separate records
- **Reminder date math at IST boundaries** — a booking on 31 Dec; a 09:00 IST run computed near UTC midnight; `checkIn == tomorrow` resolved in IST, never UTC
- R2/R4 mutual exclusion holds
- R5 is skipped when `reviews/{bookingId}` already exists
- `$4` fires at most once per calendar month per partner
- Retention deletes a 91-day-old record and spares an 89-day-old one

### Client — Flutter

- `notifications_builder_test`, `notifications_lifecycle_test`, `notifications_paid_test` **rewritten** against the repository stream instead of the deleted builder
- Feed renders from a fake repository; per-item `read` toggles; mark-all-read clears every unread
- Empty state survives
- `notification_prefs_test` extended to five toggles; essential rows render "Always on" and are not tappable
- `push_registrar_test` covers any new routes in the tap allowlist

### Rules

- A client cannot create, delete or forge a notification
- A client can set `read` and no other field
- A client cannot read another user's notifications

### Manual

On-device verification stays mandatory. Push cannot be tested in a widget test, and the 2026-07-26 QA pass found five defects that only appeared against live Firestore rules and a real auth token.

## Dependencies and sequencing

- **Nothing here reaches a user until a new build ships.** Token registration lives in the client, so no device holds an FCM token yet. This slice and the Play release are coupled — the same coupling already noted in `left.md`.
- `$1` (payment receipt) partly compensates for `RESEND_API_KEY` being unset. It is not a replacement for the emailed invoice — it is the only confirmation a payer gets until a real Resend key is configured.
- Adding the collection-group index on `items` is a **new Firestore trigger surface**. Per `left.md`, the first event-triggered 2nd-gen function deploy failed once with an Eventarc Service Agent permission error and succeeded on retry with no code change. Expect the same for `dailyNotifications` if the error appears; retry rather than debug.
