# Pawgo Pets

A pet app for Mumbai that bundles four products behind one account:

- **Discover ("Woof")** — swipe through nearby pets, match, chat, and see them on a map.
- **Services** — book walkers, sitters and groomers into live time slots, pay in-app.
- **Homestay** — request a boarding stay, the host accepts, pay to confirm, cancel for a refund.
- **Community** — a forum with categories, threads, replies and photos.

Plus chat, reviews, push/email notifications, payments and receipts, partner
payouts, ID verification, moderation (report/block, image scanning) and in-app
account deletion.

## Stack

| Part | Where | Tech |
|---|---|---|
| Mobile app (Android + iOS) | `lib/` | Flutter, Riverpod, go_router |
| Backend | `functions/`, `firestore.rules`, `storage.rules` | Firebase Auth, Firestore, Storage, FCM, App Check; Cloud Functions (TypeScript, `asia-south1`) |
| Payments | `functions/src/index.ts` | Razorpay (orders, verification, refunds, Route payouts — server-owned) |
| Admin panel | `admin/` | Next.js, Firebase Admin SDK |
| iOS CI | `codemagic.yaml` | Codemagic → TestFlight |

The UI is a port of the prototype in `Design/Pawgo Prototype.dc.html`.

## Getting started

```bash
flutter pub get
flutter run                      # pick a device or emulator
flutter analyze                  # must be clean
flutter test                     # widget + unit tests (no network — in-memory fakes)

npm --prefix functions install
npm --prefix functions test      # Functions unit tests
npm --prefix functions run build

cd admin && npm install && npm run dev   # needs admin/.env.local — see .env.local.example
```

Windows note: the project and the Pub cache sit on different drives, which
breaks Kotlin incremental builds; `android/gradle.properties` sets
`kotlin.incremental=false` to fix it. Keep it.

## Where to read next

- **`CLAUDE.md`** — architecture, conventions, build gotchas.
- **`docs/launch-checklist.md`** — everything between this build and a public release.
- **`docs/superpowers/specs/`, `docs/superpowers/plans/`** — one spec and one TDD plan per feature slice.
- **`plan.md`** — the phase-by-phase build history.
- `docs/client-feedback-2026-10-setup.md`, `docs/pawgo-pets-rename-and-ios-setup.md` — console steps for specific rounds.

## Release

App ID `com.pawgopets.app` on both platforms. Android release builds are signed
with a keystore that exists only on the owner's machine (`android/key.properties`
is git-ignored; without it the build falls back to debug signing). R8 shrinking
is on for release builds.
