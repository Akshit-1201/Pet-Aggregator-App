# Move production to the client's Firebase project (`pawgo-pets`), keep ours as dev

> **Status: documentation only — nothing implemented yet.** This describes the
> process; no code, config or console change has been made for it.
> (A trial start on 2026-10-24 was fully reverted. Leftover: an empty
> "Pawgo Pets Dev" Android app registration in `pet-aggregator-app` with no
> fingerprints — remove it in Project settings → Your apps, or reuse it in
> Phase A step 1.)

_2026-10-24 · owner request: "setup the firebase same to same all the services
and all in the client's firebase account."_

## Decisions (owner)

- **Start fresh.** `pawgo-pets` starts empty — no Auth/Firestore/Storage
  migration. The app is unpublished and existing data is test data.
- **Keep `pet-aggregator-app` as dev/staging.** Production = `pawgo-pets`.

## The constraint that shapes the design

Google allows a given **Android package name + signing SHA-1** to back an
Android OAuth client in **one** Google Cloud project only. `pet-aggregator-app`
already holds `com.pawgopets.app` + our release and debug SHA-1s (registered
2026-10-23). If both projects used `com.pawgopets.app`, Google sign-in could
only work in one of them.

**So the two environments get different Android application IDs:**

| | Production | Dev / staging |
|---|---|---|
| Firebase project | `pawgo-pets` (client) | `pet-aggregator-app` (ours) |
| Android applicationId | `com.pawgopets.app` | `com.pawgopets.app.dev` |
| App name on device | Pawgo Pets | Pawgo Pets Dev |
| Installs side by side | — | yes |
| iOS | `com.pawgopets.app` (only env on iOS) | — |
| Razorpay | test keys now → live later | test keys forever |
| Build | `flutter build apk --release --flavor prod` / Codemagic iOS | `flutter run --flavor dev` |

At migration time the `com.pawgopets.app` SHA registrations are removed from
`pet-aggregator-app` (freeing the pair) and added to `pawgo-pets`.

## How the app picks its environment

- Android **product flavors** `dev` and `prod` (`android/app/build.gradle.kts`):
  `dev` adds `applicationIdSuffix = ".dev"` and `resValue app_name`. Each
  flavor has its own `google-services.json` under
  `android/app/src/{dev,prod}/` (the Google Services plugin picks it per
  flavor).
- Dart: `lib/core/env/app_env.dart` reads Flutter's `appFlavor`
  (`package:flutter/services.dart`, set by `--flavor`). `dev` → dev; anything
  else, including iOS with no flavor → **prod**. It exposes the right
  `FirebaseOptions` (`firebase_options_dev.dart` / `firebase_options_prod.dart`)
  and the per-project Google **web client ID** (now hard-coded in
  `firebase_auth_repository.dart`).
- `main.dart` initialises Firebase with `AppEnv.current.firebaseOptions`.
- The Maps API key moves out of `AndroidManifest.xml` into a per-flavor
  `manifestPlaceholders` value (each project has its own restricted key).
- iOS keeps a single `GoogleService-Info.plist` + `Info.plist` URL schemes —
  switched to `pawgo-pets` values.

## Backend and tooling

- `.firebaserc` aliases: `dev` → `pet-aggregator-app`, `prod` → `pawgo-pets`.
  Deploys name the alias explicitly: `firebase deploy --project prod …`.
- `firestore.rules` photo-URL check: allow either project's default bucket
  (today it hard-codes `pet-aggregator-app`); rules can't read the project id.
- Functions: unchanged code; same region `asia-south1`. The new project's
  default Storage bucket **must be created in asia-south1** (the
  `moderateUploadedImage` trigger must run in the bucket's region).
- Admin panel: client config (`admin/src/lib/firebase-client.ts`) becomes
  env-driven (`NEXT_PUBLIC_FIREBASE_*`) so `.env.local` alone chooses the
  project; server side already reads `FIREBASE_PROJECT_ID` etc. Production
  admin = `pawgo-pets` with a new service-account key.
- Codemagic iOS builds production automatically (iOS has only prod).

## Who does what

- **Client (project owner):** add the developer's Google account
  (`akshitnegi2010@gmail.com`) as **Owner** on `pawgo-pets`; link a **Blaze**
  billing account. Only a billing-account holder can do the latter.
- **Owner (console clicks):** create Firestore + Storage in asia-south1, enable
  auth providers, APIs, Maps keys, secrets, deploys — Claude Code's permission
  rules block Claude from production deploys and console/IAM changes.
- **Claude:** all code/config changes, registering apps and fingerprints via the
  Firebase CLI where permitted, generating config files, tests, on-device
  verification of both flavors.

## Out of scope

iOS dev flavor (Xcode schemes) — add later if iOS QA needs a sandbox; data
migration (decided against); Razorpay live keys (separate plan:
`docs/website-and-razorpay-live-plan.md`).
