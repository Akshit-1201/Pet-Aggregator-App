# Pawgo Slice 22: App-wide back navigation — Design

> **Status:** approved design (2026-07-28). Gives every screen in the app a defined back behaviour, on both the hardware/gesture back and the on-screen affordance, driven by one shared widget. Fixes an app that currently exits on back from any tab and strands users on several screens.

## The problem this fixes

Back navigation was never designed. It was added per screen, by hand, wherever someone noticed it missing. Audited against all **38 screens**, four distinct failures:

**1. Nothing handles hardware or gesture back.** There is no `PopScope` or `WillPopScope` anywhere in `lib/`. Every back press falls through to go_router's default, so:
- Back on **any** of the five bottom-nav tabs closes the app outright. Pressing back on Profile — expecting to return Home — exits Pawgo. This is the complaint that prompted the work.
- No form warns before discarding work.
- Back during a Razorpay payment is unguarded.

**2. Fifteen screens have no on-screen back affordance.** Nine of those are correct (splash, onboarding, welcome, verify-email, and the five tab roots, which bottom nav owns). Six are not: `signup`, `location`, `pro_setup` genuinely need one, and `post_live`, `booking_confirmed`, `host_accepted` are terminal screens where the *absence* of a defined "up" is the bug.

**3. `verify_email` is a trap.** The user is signed in but unverified, and every meaningful route is gated behind verification. A plain pop bounces them straight back to the same screen with no way out but killing the app.

**4. A tapped push notification lands with no stack.** `PushRegistrar` deep-links with `context.go`, so on a cold start the user arrives deep in the app with nothing to pop — back exits immediately. Slice 21 made this reachable from 25 scenarios.

## Design decisions (settled during brainstorming)

- **One shared widget, not per-screen `PopScope`.** 38 screens each hand-rolling back handling is exactly how the current inconsistency arose. The double-tap-exit timer and confirm dialogs would be copy-pasted, and the next screen added would forget.
- **Tab → Home → confirm exit.** Back from a non-Home tab returns to Home; back on Home shows "Press back again to exit" and closes only on a second press within 2 seconds. The dominant Android pattern, and it makes an accidental exit mid-booking nearly impossible.
- **Guard only where leaving destroys work.** Confirm-on-back for `create_pet`, `pro_setup`, `host_setup` (3–5 uploaded photos each) and `new_post`. Not for two-field forms — prompting everywhere trains people to dismiss the dialog unread, which defeats it on the screens that matter.
- **Back is blocked outright while a payment verifies.** Backing out mid-verification is how money moves with no booking written.
- **`canPop` is computed, never hardcoded `false`.** Plain screens let Flutter handle back natively, preserving Android 14's predictive-back animation. Interception happens only where a screen actually needs it.
- **The on-screen button and hardware back share one code path.** `PgAppBar.onBack` calls the same resolver the OS back invokes. Today a chevron may `context.pop()` while hardware back does something else; that divergence is the root defect, not a detail.
- **`upTo` does double duty:** a forced destination for terminal screens, *and* the fallback whenever there is no stack to pop. The second role is what fixes cold-start deep links.
- **Deferred:** iOS swipe-back semantics (Android-only app), per-screen back animations, a navigation-history debug overlay, and restoring scroll position on back.

## Scope

**In scope**

- New `lib/core/navigation/pg_back_scope.dart` — the shared widget and its resolver.
- Shell back handling (tab → Home → double-tap exit) in the `StatefulShellRoute` scaffold.
- `PgBackScope` applied to the screens listed in the table below.
- The 8 screens with hand-rolled chevrons folded onto `PgAppBar`; the 6 screens missing an affordance gain one.
- Three `context.go` → `context.push` conversions (see below).
- `verify_email` back signs out.
- Widget tests per behaviour, plus a parity test and regression guards on the converted call sites.
- Emulator verification.

**Out of scope**

- No change to the router's `_protected` set, the auth redirect, or `StatefulShellRoute`'s structure.
- No change to payment, refund or booking logic — the payment screens gain a back guard reading their *existing* phase state, nothing more.
- No visual redesign. `PgAppBar` gains no new styling; screens that already look right keep looking right.
- No change to `PushRegistrar`'s route resolution (Slice 21, `resolveTapRoute`) — only the destination screens' `upTo` fallbacks.

---

## What back does on every screen

### Shell tab roots (5)

`home` · `discover` · `services` · `community` · `profile`

Non-Home tab → switch to the Home branch. On Home → "Press back again to exit" toast; a second press within **2 seconds** calls `SystemNavigator.pop()`. The timer resets after the window, so a press, a pause, and another press shows the toast again rather than exiting.

Handled once in the shell scaffold. Individual tab screens declare nothing.

### Auth funnel (6)

| Screen | Back |
|---|---|
| `splash` | Nothing — transient, auto-advances |
| `onboarding` | Steps back through pages 4→1; from page 1, exits |
| `welcome` | Exits — this is the auth root, there is nowhere up |
| `signup` | → Welcome |
| `verify_email` | **Signs out**, then → Welcome |
| `location` | No back affordance; hardware back → double-tap to exit |

Two of these need explaining.

**`verify_email` signs out.** A plain pop returns to a gated route, the redirect bounces the user back here, and they are stuck in a loop with no exit but killing the app.

**`location` has nowhere to go up to.** It is reached from `verify_email` (`verify_email_screen.dart:66`), not from signup — so by the time a user sees it the account already exists *and* is verified. Popping to signup is a dead end, and popping to verify-email loops, because the router redirects verified users off that screen. It is a required funnel step with nothing above it, so it gets the same treatment as Home: no back button, and hardware back offers a confirmed exit rather than stranding or silently doing nothing. Relaunching returns the user here with nothing lost.

`create_pet` is the step after `location` and backs to it normally (plus its dirty-check — see below), since `create_pet_screen.dart:140` already treats `location` as its predecessor.

### Terminal confirmations (5) — `upTo`

| Screen | Back goes to |
|---|---|
| `post_live` | Community |
| `booking_confirmed` | My Bookings |
| `host_accepted` | My Bookings |
| `woof_match` | Discover |
| `receipt` | Payments |

A plain pop on these walks back into a **completed** checkout or submission. `upTo` also covers arrival with no stack.

### Work-losing forms (4) — `confirmWhen`

`create_pet` (→ `location`) · `pro_setup` · `host_setup` · `new_post`

The dialog appears only when something has actually been entered. An untouched form pops silently. The dirty check is a closure over existing screen state (`_photos.isNotEmpty`, controller text) — no new state management.

### Payment (2) — `blockWhen`

`payment` · `homestay_payment`

Back refused while verification is in flight, with a brief "Payment in progress" toast. Freely poppable before checkout starts and after it resolves. Reads the screens' existing phase enum.

### Plain pop (16)

`my_bookings` · `chat_list` · `chat_conversation` · `thread` · `nearby_map` · `homestay_list` · `homestay_request` · `host_profile` · `notifications` · `payments` · `pet_profile_detail` · `blocked_users` · `settings` · `rate_review` · `booking` · `pro_profile`

`thread` additionally declares `upTo: Routes.community` as an empty-stack fallback: it is reached by `push` from the feed (where plain pop is right) **and** by `go` from `post_live` (where there is no stack). Screens reachable from a push-notification deep link follow the same rule.

---

## Architecture

One new file, `lib/core/navigation/pg_back_scope.dart`:

```dart
PgBackScope(
  upTo: Routes.community,        // forced destination + empty-stack fallback
  confirmWhen: () => _isDirty,   // ask before leaving
  blockWhen: () => _verifying,   // refuse back outright
  child: ...,
)
```

Resolution order: **block → confirm → upTo → pop**. Omit every option and it is an ordinary pop, so wrapping a screen costs nothing and reads as intent.

**`canPop` is computed:**

```
canPop = !blocked && !dirty && upTo == null && Navigator.canPop(context)
```

When true, Flutter handles back natively and the predictive-back animation survives. When false, the resolver takes over in `onPopInvokedWithResult`.

**Shared path with the on-screen button.** `PgBackScope` exposes `PgBackScope.pop(context)`, which runs the identical resolver. `PgAppBar.onBack` calls it. The button and the OS gesture cannot diverge.

**Shell handling is separate** — tab behaviour is not a per-screen concern. The `StatefulShellRoute` scaffold owns the branch switch and the exit timer, in one place for all five tabs.

**Affordance consolidation.** The 8 screens with hand-rolled chevron containers move to `PgAppBar` (identical markup already, just inlined). The 6 screens missing a button gain one. `PgAppBar` itself is unchanged apart from being used more.

## The `go` → `push` conversions

Only three call sites convert. This is deliberately narrow — the audit found four `go`-to-detail calls that are **correct as they stand**, and converting them would re-create the "back walks into a finished checkout" bug.

**Convert (going deeper):**

| Call site | Target |
|---|---|
| `discover_screen.dart:73` | `nearby` |
| `home_screen.dart:97` | `nearby` |
| `services_list_screen.dart:53` | `proSetup` |

**Leave alone (flow completions and deliberate stack-skips):**

| Call site | Why |
|---|---|
| `new_post_screen.dart:77` → `postLive` | Post submitted; `push` would let back re-enter the form |
| `payment_screen.dart:55` → `bookingConfirmed` | Payment done; back must never re-enter checkout |
| `homestay_request_screen.dart:76` → `hostAccepted` | Same |
| `post_live_screen.dart:44` → `thread` | Deliberately skips the confirmation screen on back |

Back works on all four via the destination's `upTo`, not via a stack.

The 15 `context.go(Routes.home)` calls are untouched — every one is a flow completion returning to a root.

## Error handling

| Situation | Behaviour |
|---|---|
| `upTo` set but the route does not exist | go_router throws on an unknown path, so `upTo` values are `Routes.*` constants only — a typo is a compile error, not a runtime crash |
| Back pressed while a dialog or sheet is open | The dialog's own route pops first; `PgBackScope` never sees it |
| Back pressed twice rapidly on a guarded form | The confirm dialog is a route; the second press dismisses the dialog, not the screen |
| Exit window still open when the user navigates away | The window is a stored **timestamp**, compared on the next press — not a live `Timer`. There is nothing to cancel and nothing to leak, and a stale window simply expires. |
| `confirmWhen`/`blockWhen` throws | Treated as `false` — a broken predicate must not trap the user on a screen |

## Testing

**`PgBackScope`** — `tester.binding.handlePopRoute()` simulates the system back button, so the behaviours are pinnable rather than left to manual checking.

- No options → pops normally, and `canPop` stays `true` (predictive back preserved)
- `upTo` → lands on the target even when a poppable stack exists
- `upTo` with an **empty** stack → reaches the target instead of exiting
- `confirmWhen` false → pops silently, no dialog
- `confirmWhen` true → dialog shown; cancel keeps the screen and its state; confirm leaves
- `blockWhen` true → back refused, toast shown, still on screen
- Blocked **and** dirty → block wins, no dialog

**Parity** — tapping `PgAppBar`'s chevron and firing hardware back from the same screen land in the same place. This is the invariant the design rests on.

**Shell**

- Back on Discover/Services/Community/Profile → Home, app still running
- Back on Home, first press → toast, **no exit call**
- Second press within 2s → `SystemNavigator.pop()` invoked
- Press, wait past the window, press → toast again, not an exit

**Per-screen**

- Each of the five terminal screens reaches its declared target
- `verify_email` back signs out and reaches Welcome, without bouncing
- `location` back shows the exit confirmation rather than popping to a dead end, and does not strand
- The four guarded forms prompt only when genuinely dirty
- Both payment screens refuse back while verifying, allow it before and after

**Regression guards on the three converted call sites** — navigate in, press back, land on the parent. Without these, someone "tidying" a `push` back to a `go` silently removes back again.

**Emulator verification is part of the work, not a formality.** Widget tests cannot cover the real OS gesture (edge-swipe versus button), the predictive-back animation, or actual app termination — `SystemNavigator.pop()` can only ever be asserted as a call. The 2026-07-26 on-device pass found five defects invisible to widget tests.

On-device checklist: back from each of the four non-Home tabs; double-tap exit on Home; back out of a photo-bearing form with photos attached; back during a live Razorpay verification; back from each terminal screen; back from a cold-start notification deep link; and edge-swipe versus the button on the same screen.
