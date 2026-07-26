# Pawgo Slice 21: Notification scenarios + engine — Design

> **Status:** approved design (2026-07-26). Defines **every** notification Pawgo sends, on **both channels** (push + email), and rebuilds the delivery machinery around that catalogue. Replaces the client-derived notification feed with server-authored records, folds the hand-wired email calls into the same engine, and adds the first time-based notifications the app has ever had.

## The problem this fixes

Notifications work in places, but the *system* around them doesn't exist. Four separate problems:

**1. The feed and push are two unrelated implementations.** Six triggers in `functions/src/index.ts` send pushes. Meanwhile `buildNotifications` (`lib/features/notifications/notification_item.dart:32`) re-derives a feed **client-side** from chats, reviews, bookings and stays the user can already read. Nothing connects them. They already disagree — a Woof match pushes but never appears in the feed, and a review notification ships under the *Bookings* toggle. `left.md` flags this as "worth unifying eventually".

**2. Email is a third, separate implementation.** Two emails exist — a payment receipt (`index.ts:487`) and a refund confirmation (`index.ts:892`) — both called inline from payment functions, both invisible to the notification layer. Nothing else in the app can send email, and no email is deduplicated or recorded anywhere.

**3. Much of what matters is silent on every channel.** Nothing notifies: a comment on your post, a released payout, a payout blocked for missing bank details, KYC approved, KYC rejected, or a stay request the guest just submitted. The KYC ones are sharpest — the admin panel flips `verified` and the partner is never told, so verification looks broken from their side.

**4. Nothing is time-based.** There is no scheduler. An accepted stay the guest forgets to pay for silently expires with no nudge. A pro is never reminded of tomorrow's appointment. Nobody is ever asked for a review, which is why `reviewCount` stays near zero and the ratings the marketplace runs on never accumulate.

### Two live defects this also fixes

- **The refund email misdescribes service refunds.** `sendRefundEmail` takes a `homeName` and its template reads *"Your stay at {homeName} was cancelled"*. The service caller passes `"your Dog walking with Rahul"`, producing **"Your stay at your Dog walking with Rahul was cancelled."**
- **A cancellation refunding ₹0 sends nothing.** `sendRefundEmail` is called inside `if (claim.refundAmount > 0)`, so a same-day cancellation — where the customer most wants written confirmation of *why* nothing came back — gets silence.

## ⚠️ Email does not send until Resend is configured

`RESEND_API_KEY` holds the literal string `"unset"`, and `isMailConfigured()` treats that as "email is off" — it logs a warning instead of calling Resend. **Every email in this spec is dead on arrival until a real key is set.** The placeholder exists because the Firebase CLI refuses to deploy *any* function while a declared secret has no value.

To switch email on: create a Resend account → verify a sending domain → `firebase functions:secrets:set RESEND_API_KEY` → confirm `MAIL_FROM` in `functions/src/index.ts` (currently assumes `receipts@pawgo.app`) → redeploy.

Building the email scenarios before the key exists is still correct — they deploy inert and start working the moment the key lands, with no code change. But **do not treat this slice as closing the "user gets no confirmation" gap until the key is set.** Until then, push is the only channel that actually reaches anyone.

## Design decisions (settled during brainstorming)

- **Scope is transactional + lifecycle. No marketing.** Every notification is something the recipient must act on or has money riding on. Growth pushes ("new pets near you", dormant win-backs) are explicitly out — they are what gets notification permission revoked and email marked as spam, and they'd drag in frequency caps and an unsubscribe story. Because everything here is transactional, no unsubscribe link is required.
- **Two channels, chosen per scenario, and independent.** Push is for *now*; email is for *later*. A push is gone the moment it's dismissed, so anything the user may need to produce months from now — a receipt, a refund confirmation, a booking record — goes to email as well. Chat, woofs, community and reminders are push-only; emailing them is how an app gets filtered.
- **Scheduled reminders go out in one 09:00 IST batch.** Not "whenever due" — that wakes people at 3am. Not a quiet-hours held-queue — a second moving part for no gain when every reminder is day-granular anyway. Event-driven notifications stay instant.
- **Seven categories: five user-controlled, two essential.** Messages, Bookings, Woofs, Community, Reminders are toggleable. Money and Account (refund processed, payout paid, KYC verdict) **ignore preferences**, because silently failing to tell someone their refund landed or their ID was rejected is a support incident, not a preference. Settings states this rather than hiding it.
- **Preferences gate push only, never email.** A transactional receipt is a record, not an interruption; muting push notifications must not silently stop someone's receipts.
- **The notification record is written before any channel is attempted, and regardless of preferences.** Muting a category opts you out of *interruption*, not *information*. Your booking history must not vanish from the feed because you turned off push. This is also what makes the feed trustworthy as a record, and what gives email its dedupe key.
- **Rendered text is stored, not re-rendered on the client.** Storing params and templating client-side would put the same templates in two places in two languages — precisely the drift being removed. The server catalogue is the single source of copy. English-only, Mumbai market, so nothing is lost.
- **Presentation stays on the client.** The doc stores `scenario`, `category`, `title`, `body`, `route`, `createdAt`, `read`. Emoji and accent colour are a client-side lookup keyed by category; storing `0xFF34B27B` in Firestore would be a category error.
- **Notifications are extracted out of `index.ts`.** That file is already 906 lines carrying payments, refunds, payouts, deletion and masking. Adding 15 scenarios, an email layer and a scheduler in place would make it unmaintainable.
- **Now is the only free moment for the migration.** Replacing the derived feed means every user's feed starts empty. The database holds 4 users, 2 pets and 2 posts from the QA run and **no build has shipped**, so nobody is affected. That window closes at internal testing.
- **Deferred:** OS-level notification grouping ("3 new messages" as one), rich media in pushes, per-tab badges, digest emails, SMS/WhatsApp, per-scenario (rather than per-category) preferences, and PDF invoice attachments.

## Scope

**In scope**

- New `functions/src/notify/` module: `catalog.ts`, `notify.ts`, `email.ts`, `triggers.ts`, `reminders.ts`.
- `sendPushTo` and the six existing push triggers **move out of** `index.ts`; `index.ts` calls `notify()` where it currently inlines push or email.
- `invoice.ts` generalised into a reusable email shell and absorbed by `email.ts`; the receipt table layout survives as one template variant.
- 15 new scenarios (2 booking-confirmation, 1 community, 5 money, 2 account, 5 reminders).
- Email on 16 scenarios — 14 new, plus the two existing emails re-homed with their defects fixed.
- New scheduled Function `dailyNotifications` (09:00 IST): five reminder types, the payout-blocked sweep, and retention.
- New Firestore collection `notifications/{uid}/items/{key}` + rules + indexes.
- Client: `NotificationRepository` interface + Firestore implementation; `buildNotifications` **deleted**; feed reads the stream; per-item `read` replaces the global `notifsSeenAt`.
- Settings: two new toggles (Community, Reminders) + an "Always on" treatment for the essential tier.
- `vitest` added to `functions/` (no test runner exists there today).
- Rewrites of the four existing Dart tests that target the deleted builder.

**Out of scope**

- No change to `PushService`, token storage, or token rotation — that layer works. `PushRegistrar._handleTap` only gains any new routes in its allowlist.
- No change to payment, refund or payout *mechanics*, beyond calling `notify()` where they currently inline a send or send nothing.
- No new UI screens. The Notifications screen changes its data source, not its layout.
- No backfill for events that already happened.
- Setting the Resend key and verifying a sending domain — configuration, not code.

---

## The scenario catalogue

**25 scenarios.** 10 exist today, 15 are new. IDs are the literal scenario ids used in code.

Categories: `messages` · `bookings` · `woofs` · `community` · `reminders` · `money` *(essential)* · `account` *(essential)*

### Event-driven — fire immediately

| ID | Scenario | Recipient | Category | Push | Email | Status |
|---|---|---|---|:--:|:--:|---|
| `MSG1` | New chat message | Other participant; suppressed if they blocked the sender | messages | ✅ | — | exists |
| `BOOK1` | Service booking paid | Pro | bookings | ✅ | ✅ | push exists |
| `BOOK2` | Service booking cancelled | Pro | bookings | ✅ | ✅ | push exists |
| `BOOK3` | Stay request received | Host | bookings | ✅ | ✅ | push exists |
| `BOOK4` | Stay request accepted — pay to confirm | Guest | bookings | ✅ | ✅ | push exists |
| `BOOK5` | Stay request declined | Guest | bookings | ✅ | ✅ | push exists |
| `BOOK6` | Stay paid & confirmed | Host | bookings | ✅ | ✅ | push exists |
| `BOOK7` | Stay cancelled | Host | bookings | ✅ | ✅ | push exists |
| `BOOK8` | Review received | Pro / host | bookings | ✅ | — | exists |
| **`BOOK9`** | **Stay request submitted — we've got it** | Guest | bookings | — | ✅ | **new** |
| **`BOOK10`** | **Service booking created — pay to confirm** | Customer | bookings | — | ✅ | **new** |
| `WOOF1` | Reciprocal woof → match | Both owners | woofs | ✅ | — | exists |
| **`COMM1`** | **Comment on your post** | Post author; skipped on your own post | community | ✅ | — | **new** |
| **`PAY1`** | **Payment received — receipt** | Payer | money *(essential)* | ✅ | ✅ | **push new**, email exists |
| **`PAY2`** | **Refund processed** | Customer | money *(essential)* | ✅ | ✅ | **push new**, email exists *(defect fixed)* |
| **`PAY3`** | **Cancelled — no refund due** | Customer | money *(essential)* | ✅ | ✅ | **new** |
| **`PAY4`** | **Payout sent to your bank** | Pro / host | money *(essential)* | ✅ | ✅ | **new** |
| **`PAY5`** | **Earnings waiting — add bank details** | Partner | money *(essential)* | ✅ | ✅ | **new** *(nightly, see below)* |
| **`ACC1`** | **Verified — your KYC was approved** | Partner | account *(essential)* | ✅ | ✅ | **new** |
| **`ACC2`** | **KYC rejected + reason** | Partner | account *(essential)* | ✅ | ✅ | **new** |

**`BOOK9` and `BOOK10` are email-only on purpose.** The user just performed the action in the app and is looking at a confirmation screen — a push telling them what they just did is noise. An email is still worth sending, because it's the record they'll search for later. This is the clearest demonstration that the two channels are chosen independently.

**`PAY5` is the one row here that isn't event-driven.** There is no event for *"still hasn't added bank details"* — it's a standing condition. The nightly job finds it (`payouts` where `status == 'owed'` whose partner has no linked account) and sends at most once per calendar month. It's grouped here because it belongs to the essential money category.

### Scheduled — 09:00 IST daily batch

All push-only. These are nudges, not records.

| ID | Scenario | Condition | Recipient | Category |
|---|---|---|---|---|
| **`REM1`** | Pay today or this booking expires | `bookings`: `status == 'pending'`, `date == today` | Customer | reminders |
| **`REM2`** | Pay to confirm your stay | `homestayBookings`: `status == 'accepted'`, `checkIn == tomorrow` | Guest | reminders |
| **`REM3`** | Appointment tomorrow | `bookings`: `status == 'confirmed'`, `date == tomorrow` | Customer + pro | reminders |
| **`REM4`** | Check-in tomorrow | `homestayBookings`: `status == 'paid'`, `checkIn == tomorrow` | Guest + host | reminders |
| **`REM5`** | How was it? Leave a review | service `confirmed` with `date == yesterday`, or stay `paid` with `checkOut == yesterday`, and no `reviews/{bookingId}` | Customer | reminders |

`REM2` and `REM4` are mutually exclusive by status — an accepted-but-unpaid stay gets the payment nudge, a paid one gets the check-in reminder, never both.

### Deliberate omissions

- **A newly created unpaid service booking stays silent *for the pro*.** They have nothing to act on until money lands. (`BOOK10` notifies the *customer*, who does.) This preserves the existing reasoning in `onServiceBookingWritten`.
- **No reply-to-comment scenario.** `Comment` has no parent field — comments are flat.
- **No moderation-outcome notification.** Telling a reported user they were reported mostly invites retaliation against whoever reported them.
- **No email for chat, woofs, community or reminders.** High-volume, low-durability, and the fastest route to a spam folder that then swallows the receipts.

---

## Architecture

```
functions/src/notify/
  catalog.ts    — the 25 scenarios, declared once
  notify.ts     — the single send path (record → push → email)
  email.ts      — the shared email shell + Resend transport
  triggers.ts   — Firestore triggers: resolve audience + params, call notify()
  reminders.ts  — the 09:00 IST job: 5 reminders + PAY5 sweep + retention
```

A catalogue entry is the entire contract for a scenario:

```ts
{
  id: "REM4",
  category: "reminders",       // → which toggle gates the push
  essential: false,            // true = push ignores preferences
  collapse: false,             // true = overwrite the existing record
  route: "/bookings",
  channels: ["push"],          // ["push"] | ["email"] | ["push", "email"]
  render: (p) => ({ title: `${p.petName} checks in tomorrow`,
                    body:  `${p.homeName} · ${p.checkInLabel}` }),
  // present only when channels includes "email"
  email: (p) => ({ subject: …, heading: …, subheading: …,
                   rows?: InvoiceLine[], paragraphs?: string[], footer?: string }),
}
```

`notify(scenarioId, uid, params, dedupeKey)` is the **only** way anything sends:

1. Look up the scenario. An unknown id is a `tsc` error, not a runtime one — the catalogue is a typed map.
2. Write `notifications/{uid}/items/{dedupeKey}`. If the write was a no-op re-delivery, stop.
3. **Push**, if `channels` includes it *and* (`essential` or the category toggle is on). Absent preference field means on.
4. **Email**, if `channels` includes it. Resolved via `verifiedEmailFor(uid)` — never an address the client supplied. Not gated by preferences.

Steps 3 and 4 are independent: an email failure must not suppress the push, and vice versa. Both are wrapped; neither throws.

### The email shell

`invoice.ts` already solved the hard part — table-based HTML with inline styles, the only layout that renders consistently in Gmail, Outlook and Apple Mail. That is generalised rather than rewritten:

```ts
renderEmail({ heading, subheading, rows?, paragraphs?, footer? }): { html, text }
```

The existing receipt is this shell with `rows` (the line-item table). The refund confirmation is the same shell with `paragraphs`. Every new email is one more call. The Pawgo header, cream background, brand bar and footer live in one place.

Both `sendInvoiceEmail` and `sendRefundEmail` collapse into a single `sendEmail(to, subject, body)` over Resend, keeping the existing contract: **returns false, never throws** — the money has already moved by the time email runs, and a mail outage must never surface as a failed payment. `isMailConfigured()` and the `"unset"` short-circuit are preserved exactly.

### Record shape

`notifications/{uid}/items/{dedupeKey}`:

| Field | Type | Note |
|---|---|---|
| `scenario` | string | catalogue id (`"PAY2"`) |
| `category` | string | one of the seven |
| `title`, `body` | string | rendered server-side at send time |
| `route` | string | deep-link target |
| `createdAt` | int millis | sort key; retention key |
| `read` | bool | per-item, replaces the global `notifsSeenAt` |

Email-only scenarios still write a record — it's what makes the in-app feed a complete history and what dedupes the email.

### Client changes

| Piece | Change |
|---|---|
| `NotificationRepository` | New interface + `FirestoreNotificationRepository`: `watch(uid)`, `markRead(id)`, `markAllRead(uid)` |
| `buildNotifications` | **Deleted** — ~110 lines of client derivation replaced by a stream read |
| `NotificationItem` | Becomes a mapped model; keeps the category → emoji/accent lookup |
| `UserProfile.notifsSeenAt` | Removed, with `markNotificationsSeen` — dead once `read` is per-item |
| `NotificationPrefs` | Gains `notifyCommunity`, `notifyReminders`; both default ON when absent |
| Settings | Two new toggles; essential rows render "Always on" and are not tappable |
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

Notifications are server-authored records. A client that can create one can forge *"your refund was processed"*; a client that can delete one can hide a KYC rejection. The Admin SDK bypasses rules, so triggers write freely.

---

## Idempotency

Firestore triggers are **at-least-once** — the payments work already hit a redelivery in production. The doc id **is** the dedupe key, so a redelivery re-writes the same path instead of creating a second record, and both channels are skipped when the write was a no-op.

This is a real gain for email: today's receipt is sent from a callable with nothing preventing a duplicate. Under `notify()`, **the notification record is the send-once guard for email too** — nobody gets two receipts for one payment.

| Scenario | Dedupe key | Effect |
|---|---|---|
| `MSG1` | `chat_{chatId}` | **collapses** |
| `COMM1` | `post_{postId}` | **collapses** |
| `BOOK1`–`BOOK7` | `{id}_{bookingId}` | once per transition |
| `BOOK8` | `BOOK8_{bookingId}` | once |
| `BOOK9` / `BOOK10` | `{id}_{bookingId}` | once |
| `WOOF1` | `WOOF1_{otherUid}` | once per pair |
| `PAY1` | `PAY1_{paymentId}` | once |
| `PAY2` / `PAY3` | `{id}_{bookingId}` | once |
| `PAY4` | `PAY4_{payoutId}` | once |
| `PAY5` | `PAY5_{YYYY-MM}` | at most monthly |
| `ACC1` / `ACC2` | `{id}_{reviewedAt}` | once per verdict; re-submission allowed |
| `REM1`–`REM5` | `{id}_{bookingId}` | once, ever |

Keys are scoped per user — records live under `notifications/{uid}/items/`, so `REM4` sending to both guest and host uses the identical key at two different paths with no collision.

**Collapsing** is the one behaviour that is not plain dedupe. A 40-message conversation must not become 40 feed rows; today's derived feed correctly shows one row per chat. `collapse: true` scenarios overwrite their record in place (new `title`/`body`/`createdAt`, `read` reset to false) while still pushing on every event. **The push is per-event; the feed row is per-thread.** Comments on a busy post get the same treatment. No collapsing scenario sends email.

## Data flow

**Event path:** Firestore write (or payment callable) → resolve recipient + params → `notify()` → record → push → email.

**Scheduled path:** 09:00 IST cron → five date-equality queries → `notify()` per hit → `PAY5` sweep → retention sweep.

Both `Booking.date` and `HomestayBooking.checkIn`/`checkOut` serialise as plain `YYYY-MM-DD` strings, so the reminder queries are cheap equality lookups rather than range scans. Required composite indexes in `firestore.indexes.json`:

- `bookings`: `status` ASC + `date` ASC (serves `REM1`, `REM3`, `REM5`)
- `homestayBookings`: `status` ASC + `checkIn` ASC (serves `REM2`, `REM4`)
- `homestayBookings`: `status` ASC + `checkOut` ASC (serves `REM5`)
- collection group `items`: `createdAt` ASC (serves retention)

The `PAY5` sweep queries `payouts` on `status` alone — single-field, automatically indexed.

**Retention.** The nightly job deletes records older than 90 days via a collection-group query on `items`, unread included. Without it the collection only ever grows; the feed is a rolling window, not an archive. Email is unaffected — it lives in the recipient's mailbox, which is the point of sending it.

## Error handling

| Failure | Behaviour |
|---|---|
| Push send throws | Logged, swallowed. The record is written and email still attempted |
| Email send fails / Resend rejects | Logged, returns false. Push and the record are unaffected |
| `RESEND_API_KEY` unset | `isMailConfigured()` short-circuits with a warning — no doomed API call |
| No verified email for the user | Skip email, log. Push still sent |
| Token rejected (`not-registered` / `invalid`) | Pruned from `fcmTokens` — unchanged from today |
| Recipient doc missing | Skip and log. A deleted account must not crash a trigger |
| One reminder query fails | Wrapped independently — the other four, `PAY5` and retention still run |
| Record write fails | Logged; both channels still attempted. Losing the feed row beats losing everything |
| Unknown scenario id | Impossible at runtime — typed catalogue map, caught by `tsc` |

`notify()` never throws. A notification that fails must not roll back the booking, message or payment that triggered it — the existing `sendPushTo` and `sendInvoiceEmail` contracts, now applied uniformly.

## Testing

### Server — `vitest` added to `functions/`

New infrastructure, and justified: 25 render functions, 15 email templates and IST date arithmetic are exactly where silent bugs live, and there is no runner today.

- Every catalogue entry renders non-empty `title` and `body` from representative params
- Every `channels: [… "email"]` entry has an `email` renderer, and produces a non-empty subject, HTML and plain-text alternative
- **The service refund email never says "your stay at"** — the defect that motivated this
- **`PAY3` sends on a ₹0 refund** — the silent case today
- HTML escaping holds: a pet named `<script>` cannot inject into an email
- Dedupe keys are stable across repeated calls and distinct across scenarios
- A redelivered event sends neither a second push nor a second email
- `essential: true` scenarios push with the category toggle off; non-essential ones don't
- **Preferences never suppress email**
- The record is written even when preferences suppress the push
- Collapsing scenarios overwrite in place; non-collapsing create separate records
- **Reminder date math at IST boundaries** — a booking on 31 Dec; a 09:00 IST run computed near UTC midnight; `checkIn == tomorrow` resolved in IST, never UTC
- `REM2`/`REM4` mutual exclusion holds; `REM5` skipped when `reviews/{bookingId}` exists
- `PAY5` fires at most once per calendar month per partner
- Retention deletes a 91-day-old record and spares an 89-day-old one
- With `RESEND_API_KEY` unset, email is skipped and **push still sends**

### Client — Flutter

- `notifications_builder_test`, `notifications_lifecycle_test`, `notifications_paid_test` **rewritten** against the repository stream instead of the deleted builder
- Feed renders from a fake repository; per-item `read` toggles; mark-all-read clears every unread
- Email-only scenarios still appear in the feed
- Empty state survives
- `notification_prefs_test` extended to five toggles; essential rows render "Always on" and are not tappable
- `push_registrar_test` covers any new routes in the tap allowlist

### Rules

- A client cannot create, delete or forge a notification
- A client can set `read` and no other field
- A client cannot read another user's notifications

### Manual

On-device verification stays mandatory. Push cannot be tested in a widget test, and the 2026-07-26 QA pass found five defects that only appeared against live Firestore rules and a real auth token. Email needs one end-to-end send against a real Resend key before launch — rendering is only truly verified in a real Gmail and Outlook client.

## Dependencies and sequencing

- **Push reaches nobody until a new build ships.** Token registration lives in the client, so no device holds an FCM token yet. This slice and the Play release are coupled — the coupling already noted in `left.md`.
- **Email reaches nobody until `RESEND_API_KEY` is set.** See the warning above. The code deploys inert and activates on configuration alone.
- `PAY1` compensates for the unset key only on the push channel. Until Resend is configured, a payer's sole confirmation is a push notification and the in-app record.
- `dailyNotifications` is a **new scheduled Function**, and the collection-group index adds a new trigger surface. Per `left.md`, the project's first event-triggered 2nd-gen function deploy failed once with an Eventarc Service Agent permission error and succeeded on retry with no code change. Expect the same; retry rather than debug.
