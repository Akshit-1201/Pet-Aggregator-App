# Pawgo — Full Project Build Plan

## Context

**Pawgo** is a Flutter + Firebase "pet aggregator" app (Android-only, Mumbai market) bundling four products behind one account: Discovery/Matching ("Woof"), a Services marketplace, Homestay boarding, and a Community forum.

The complete UI already exists as a **30-screen prototype** the owner designed in claude.ai/design
(<https://claude.ai/design/p/4d0931d4-afa6-488d-b794-580e0c63474f?file=Pawgo+Prototype.dc.html>), imported into the repo at **`design/Pawgo Prototype.dc.html`**. **We are porting that prototype into Flutter — not designing anything new.** The prototype is the single source of truth for every colour, font, radius, and layout.

**Build strategy (updated 2026-07-08):** we build one slice at a time so the app is always runnable and reviewable against the prototype. Slice 1 (Phases 1–2 below) built the design system + onboarding/auth/Home UI against **mock data behind a repository seam**. **From Slice 2 on, the app goes real** — per the owner's directive it must be a *live* app, not a demo/mock, so we wire the actual Firebase backend now and build each remaining pillar directly against **live data** (no separate static/mock stage). The repository-interface seam means Firebase implementations slot in at the provider layer without rewriting screens. Maps and payments still arrive in their own later slices. **This supersedes the earlier "all 30 screens static first, wire Firebase at Phase 8" ordering:** backend wiring (auth + Firestore + profiles) moves up to now, and the pillar phases below (3–7), though written as "static", are now built on the real backend.

**Outcome:** a Play-Store-ready Android app that looks the same as the Pawgo prototype and is backed by Firebase (auth, database, storage, notifications), Google Maps, and Razorpay payments.

## Design fidelity — how we keep it "same to same"

1. **Source of truth:** `design/Pawgo Prototype.dc.html`. Its top `<style>` block holds the exact design tokens (`--brand:#F59E2E`, cream `--bg:#FBF1E8`, Poppins + Inter, full **light and dark** themes). Each screen's exact markup lives in a labelled `<!-- SCREEN -->` block.
2. **Tokens copied verbatim** into a Flutter theme layer (`PgColors`, `PgText`, `PgRadius`) — screens never re-guess the palette.
3. **Per-screen porting:** for each screen we read its exact block in the design file, reproduce structure with shared widgets, and match spacing/colour **by eye** against the prototype's rendered output.
4. **Honest caveat:** this is a faithful Flutter *re-implementation* (HTML/CSS → real widgets), matched visually — not a pixel-identical export. Intentional deviations: the prototype's browser **phone-frame bezel** and **fake status bar** are dropped (the real device fills the screen); CSS animations are reproduced with cheap Flutter equivalents.

## Tech stack & conventions

- Flutter (Android), Dart. Navigation `go_router`; state `flutter_riverpod`; fonts `google_fonts`.
- Firebase: auth, firestore, storage, messaging, functions, app_check (installed). Maps: `google_maps_flutter` + `geoflutterfire_plus`. Payments: `razorpay_flutter`.
- **Feature-first** folders under `lib/` (`core/theme`, `core/widgets`, `core/router`, `features/<pillar>`, `data/`).
- **Repository-interface seam:** UI reads data only through abstract repositories exposed via Riverpod; `Mock*` implementations now, Firebase implementations later — swapped at the provider layer.
- Windows build note: keep `android/gradle.properties → kotlin.incremental=false` (cross-drive C:/D: Kotlin fix); run `flutter clean` if a "different roots" error appears.
- Each task is TDD where practical (widget tests per screen), ends `flutter analyze`-clean, and is committed.

---

## Phase 0 — Environment & scaffold ✅ DONE

**Goal:** a building Flutter+Firebase project with the design imported.
**Done:** Flutter app scaffold; Firebase initialised in `lib/main.dart`; 10 packages installed and compiling; Windows cross-drive build fixed; prototype imported to `design/`; Slice-1 spec + plan written under `docs/superpowers/`; git initialised.
**Verify:** `flutter build apk --debug` succeeds (already confirmed).

## Phase 1 — Design-system foundation ✅ DONE (Slice 1, 2026-07-08)

**Goal:** the reusable base every screen is built from. No feature screens yet.
**What we need:** `go_router`, `flutter_riverpod`, `google_fonts` (add to `pubspec.yaml`).
**How we'll do it:**
- `lib/core/theme/`: `PgColors` (light + dark token sets from the design file, read via a `context.pg` extension), `PgText` (Poppins/Inter helpers), `PgRadius`/`PgGap`, `PgTheme` (`ThemeData`).
- `lib/core/widgets/`: shared `Pg*` widgets that encapsulate all styling — `PgPrimaryButton`, `PgGhostButton`, `PgField`, `PgChoiceCard`, `PgToggle`, `PgPageDots`, `PgChip`, `PgAppBar`, `PgImageSlot`, `PgBottomNav`, `PgScreenScaffold`.
- `lib/core/router/`: `go_router` config — full-screen routes for onboarding/auth; a `StatefulShellRoute.indexedStack` hosting the persistent `PgBottomNav` for the five tabs.
- `lib/data/`: models (`PetProfile`, `UserProfile`, `Role`, `Species`), `mock/` data, and repository interfaces + `Mock*` impls exposed via Riverpod.
- `lib/main.dart` → `runApp(ProviderScope(child: PawgoApp()))`; `lib/app.dart` → `MaterialApp.router`.
**Deliverable:** app boots into a themed shell with working bottom-nav navigation between placeholder tabs.
**Detailed task breakdown already exists:** `docs/superpowers/plans/2026-07-07-pawgo-foundation-onboarding.md` (Tasks 1–9).
**Verify:** `flutter test` (theme + widget + router tests) green; `flutter run` shows themed placeholder tabs.

## Phase 2 — Onboarding & Auth (static) ✅ DONE (Slice 1, 2026-07-08)

> Delivered together with Phase 1 as "Slice 1": Splash → Onboarding ×4 → Welcome → Sign-up → Location → Create Pet → static Home. 20 widget tests, `flutter analyze` clean, debug APK builds, verified on the emulator. Auth/onboarding were display-only here; **Slice 2 (below) makes them real.**

**Goal:** the entry flow, pixel-faithful, mock-only.
**Screens (design lines):** Splash (111–132), Onboarding ×4 (134–249), Welcome/Login (251–282), Sign-up + Role (284–319), Location (321–337), Create Pet (339–372).
**How we'll do it:** each screen is thin composition over Phase-1 widgets; navigation wired with `go_router`; role/species/toggle selections use local state; login is visual-only (no real OTP yet). Finishing the flow lands on the Home tab.
**Detailed task breakdown already exists:** same plan file (Tasks 10–17, incl. static Home feed + manual verification).
**Verify:** widget test per screen; manually walk Splash → Onboarding → Welcome → Sign-up → Location → Create Pet → Home on the emulator; eyeball against the prototype.

## Phase 2R — Go Real: Firebase Auth + Firestore data layer ⬅ CURRENT (Slice 2)

**Goal:** turn Slice 1's mock app into a **live, Firebase-backed app** — real accounts and real profiles/pets — by swapping implementations behind the existing repository seam. This pulls the auth + Firestore + profiles portion of the old Phase 8 forward, because a real-time Discover (Phase 3) needs a real signed-in user and real pet data.
**What we need:** Firebase Console for `pet-aggregator-app` — enable **Email/Password** auth and **create the Firestore database**; `firebase login` to deploy rules. (Phone OTP, Storage uploads, Maps, Functions, App Check stay deferred.)
**How we'll do it:**
- Auth: `AuthRepository` → `FirebaseAuthRepository` (email/password sign-up/in/out + auth-state stream); Welcome/Sign-up screens become real forms; auth-aware `go_router` redirect; Splash routes on real auth state.
- Firestore: `users/{uid}` and `pets/{petId}` collections; onboarding writes real docs (Sign-up → user; Create Pet → pet); `PetRepository`/`UserRepository` Firebase impls behind Riverpod; Home streams live pets (`AsyncValue` loading/empty/error/data).
- Security rules committed to `firestore.rules` + deployed via CLI.
- TDD with in-memory fakes behind the interfaces (no network in tests).
**Spec:** `docs/superpowers/specs/2026-07-08-pawgo-real-backend-auth-firestore-design.md` (detailed TDD plan to follow under `docs/superpowers/plans/`).
**Verify:** create an account (persists in Firestore), add a pet, sign out/in, session survives restart, Home shows live data; `flutter test` green, `flutter analyze` clean, emulator walkthrough against the real project.

> **Note on Phases 3–7 below:** written as "(static)/mock-only" under the original plan, they are **now built against the real backend** delivered here — each pillar's screens read/write live Firestore through the repository seam. Maps (Phase 9) and payments (Phase 10) remain the only deferred integrations, so those specific screens stay stylised/mock until then.

## Phase 3 — Discovery "Woof" (on live data) ✅ DONE (Slice 3, 2026-07-11)

> Delivered: drag-to-swipe deck of live Firestore pets (excludes own + already-swiped), real Woof/Pass persisted to a `swipes` collection (rules + composite index deployed), **reciprocal-woof match** celebration, and a faux-map Nearby screen with a live pet list. `PgSwipeCard` gesture widget + `SwipeRepository` seam. 42 unit/widget tests + an emulator integration test (swipes + reciprocity) green; analyze clean; APK builds. Spec/plan: `docs/superpowers/{specs,plans}/2026-07-08-pawgo-discover-woof*.md`. Deferred as planned: photos, real map/geo distance, pet-profile detail, chat (match "Send a message" → coming-soon).

**Goal:** the social core, matching the prototype.
**Screens (design lines):** Home Feed (374–437, refined from Phase 2's static version), Discover swipe deck (439–475), Woof Match (477–494), Nearby Map static (496–546), Pet Profile (petprofile block).
**What we need:** a swipeable card widget (draggable deck with PASS/WOOF overlays), a static map mock (the prototype uses a stylised map background + pins — real Google Maps arrives in Phase 9).
**How we'll do it:** build `SwipeDeck` reproducing the drag/threshold + rotation and the WOOF/PASS stamps; Woof Match celebration screen (confetti/animation); Nearby as the prototype's stylised static map + bottom sheet list; Pet Profile detail. All fed by `nearbyPetsProvider` mock data.
**Verify:** widget tests (deck renders card, buttons Woof/pass, match screen shows); manual swipe on emulator; compare to prototype.

## Phase 4 — Services marketplace (on live data) — split into 4a + 4b

> **Slice 4a (supply & browse) ✅ DONE (2026-07-12):** `pros/{uid}` collection + `Pro`/`ServiceType` models + `ProRepository` seam; Pro-setup screen (servicePro writes a listing), Services list (live pros, category filter, setup banner), Pro profile. "Book" → coming-soon snackbar. 50 tests + emulator integration (pros) green; `pros` rules deployed. Spec/plan: `docs/superpowers/*/2026-07-11-pawgo-services-4a-supply-browse*.md`.
> **Slice 4b (booking & payment) — NEXT:** `bookings` collection; Booking (date/time/pet) → Payment (UI-only, Razorpay deferred to Phase 10) → Confirmed; wires the "Book" button.

**Goal:** browse-and-book UI, mock-only.
**Screens:** Services List (categories + pro cards), Pro Profile (rate/experience/reviews/availability), Booking (date/time), Payment (UI only — no real gateway yet), Booking Confirmed.
**What we need:** models `ServicePro`, `Booking`; mock lists; a date/time selection UI.
**How we'll do it:** compose list/detail screens over shared widgets; booking flow updates local state; the Payment screen is a faithful static reproduction (Razorpay wiring is Phase 10).
**Verify:** widget tests for list/detail/booking; manual flow Category → Pro → Book → Pay (mock) → Confirmed; compare to prototype.

## Phase 5 — Homestay (static)

**Goal:** the Airbnb-style boarding UI, mock-only.
**Screens:** Homestay List, Host Profile (home/household/pets/photos/price/reviews), Homestay Request (dates), Host Accepted.
**What we need:** models `Host`, `HomestayRequest`; mock hosts; a date-range UI; the host-verification badge treatment.
**How we'll do it:** reuse the Services booking spine where the prototype does; add host-specific detail sections.
**Verify:** widget tests; manual flow Search → Host → Request dates → Accepted; compare to prototype.

## Phase 6 — Community (static)

**Goal:** the forum UI, mock-only.
**Screens:** Community Feed (categories: Health/Training/Lost & Found), New Post, Thread Detail (threaded replies), Post Live.
**What we need:** models `Post`, `Reply`, `Category`; mock threads.
**How we'll do it:** feed list with category chips, post composer, threaded detail view; report affordance (visual).
**Verify:** widget tests; manual browse/post/reply flow; compare to prototype.

## Phase 7 — Shared & cross-cutting screens (static)

**Goal:** finish the remaining prototype screens.
**Screens:** Chat List, Chat Conversation (request-and-accept model), Notifications, Profile, Settings, Rate & Review — plus persistent-nav polish, toasts, and confetti.
**How we'll do it:** compose over shared widgets; wire the theme toggle in Settings (light/dark already defined); Rate & Review reusable across bookings/stays.
**Verify:** widget tests; every prototype screen now reachable and matching; full walkthrough on emulator.

> End of Phase 7 = the **entire prototype reproduced as a runnable static app** (all 30 screens), which is the "same to same" milestone.

## Phase 8 — Backend wiring (Firebase) — remaining integrations

> **Core backend now lands earlier (Phase 2R / Slice 2):** email/password auth, the `users`/`pets` Firestore collections + rules, real onboarding writes, auth-state routing, and live Home data. This phase covers what's left once the other pillars exist.

**Goal:** finish the backend for all pillars — remaining collections, Storage, messaging, phone OTP, App Check, Functions.
**What we need:** Firebase Console — add **Phone (OTP)** auth as a second method (+ app **SHA-1/SHA-256** fingerprints), enable **Storage** with security rules, enable **App Check** (Play Integrity), Blaze plan for Functions.
**How we'll do it:**
- Auth: add phone-OTP as an alternative sign-in (email/password + auth-state routing already shipped in Phase 2R).
- Firestore: add the remaining collections (woofs, services, bookings, homestays, posts, chats) alongside the `users`/`pets` from Phase 2R; implement Firebase-backed repositories behind the **existing interfaces** — screens unchanged.
- Storage: pet photos + host verification documents (upload from Create Pet / host application).
- Messaging: FCM push (Woof, booking, reply, "nearby") + notification preferences.
- Security rules + App Check before any real data flows.
**Verify:** sign in with a real OTP; create a pet that persists in Firestore; upload a photo; receive a test push; run against the Firebase emulator suite where possible.

## Phase 9 — Maps & geo (Nearby)

**Goal:** the real "pets near you, within 2 km, closest first" map.
**What we need:** Google Cloud project with **Maps SDK for Android** enabled, an **API key** (restricted to the app package + SHA-1), billing + a budget alert; key added to `AndroidManifest.xml`.
**How we'll do it:** replace the Phase-3 static map with `google_maps_flutter` (pins/clustering); store each pet's location as a **geohash** and query with `geoflutterfire_plus` for radius/"closest first"; approximate-area privacy (never exact address).
**Verify:** map renders with real pins on the emulator; radius filter returns correct nearby pets.

## Phase 10 — Payments & Cloud Functions

**Goal:** real in-app payments and the server-only logic.
**What we need:** a **Razorpay** account (test then live/KYC); Firebase **Cloud Functions** (Blaze).
**How we'll do it:**
- Payments: `razorpay_flutter` checkout; **order creation + signature verification in Cloud Functions** (never trust the client); mark bookings paid only after server verification.
- Payouts: **Razorpay Route** to split commission and settle to pros/hosts (ties into KYC/verification).
- Cloud Functions also host the **sensitive-info message filter** (block/mask phone/address in chat) and booking transactions.
**Verify:** test-mode payment completes and the booking flips to paid only via the verified webhook; a chat message containing a phone number is masked/blocked.

## Phase 11 — Launch prep (Google Play)

**Goal:** ship to the Play Store.
**What we need:** release **signing key**; Play Console listing (name, description, screenshots, category); **privacy policy**, **data-safety** form, in-app **account deletion**, **age rating**; App Check enforced.
**How we'll do it:** configure release build + signing; build an **app bundle** (`flutter build appbundle`); complete store listing and required policies; internal testing track → production.
**Verify:** signed release bundle installs and runs; Play pre-launch report clean; internal testers complete core flows.

---

## Phase 12 — Admin & Moderation Panel (separate web app)

**Goal:** an internal web dashboard for staff/engineers to run the platform — verification, moderation, users, bookings/disputes, payments oversight — on the **same Firebase backend** as the mobile app. This is **not** part of the Flutter app.

**Sequencing (parallel workstream, not after launch):** starts once the **Phase 8 Firestore data model** exists. Its **verification + content-moderation + user-management** modules are a **prerequisite for the Phase 11 launch** — a customer-facing UGC + marketplace app cannot open to the public without them. Analytics, finance, and broadcast modules can follow post-launch.

**Stack (chosen):** **Next.js (React + TypeScript)** admin app; UI via a component library (shadcn/ui or MUI) + a data-table lib (TanStack Table); **Firebase Admin SDK** server-side (Next.js server actions / API routes or Cloud Functions). Separate repo or an `/admin` workspace, **same Firebase project**. Deployed on Vercel or Firebase Hosting + Cloud Run.

**Security architecture (the important part at scale):**
- **Separate admin auth** from consumer phone-OTP: **Google SSO restricted to the company domain**, gated by Firebase Auth **custom claims** (`admin`, `role`) set only via an Admin-SDK Cloud Function — never self-serve.
- **RBAC roles:** super-admin, moderator, support, finance — each restricted to its own modules.
- **All privileged mutations go through Cloud Functions (Admin SDK)** that verify the caller's claim, perform the write, and append an **immutable audit-log entry**. The browser never writes admin data directly to Firestore; consumer security rules stay locked down.
- New Firestore collections to support it: `reports`, `verificationRequests`, `auditLogs`, `adminRoles`.

**Modules / what's on it:**
1. **Dashboard** — KPIs: users, DAU/MAU, bookings, GMV, open-report and pending-verification queues.
2. **User management** — search/view profiles + pets; suspend/ban/reactivate; manage roles; process account-deletion requests (also a Play requirement).
3. **Verification (KYC)** — queue of service-pro / homestay-host applications; view submitted documents from Storage (signed URLs); approve/reject → sets `verified` + role; reason logged.
4. **Content moderation** — unified queue of reported posts, replies, chats and listings; actions: dismiss / warn / remove content / suspend user.
5. **Bookings & disputes** — service + homestay bookings, status, participants; issue refunds (via a Razorpay Cloud Function); dispute notes.
6. **Payments & payouts** — transactions, commission, Razorpay Route payout status, manual refund/adjustment.
7. **Community management** — categories CRUD; pin / lock / remove threads.
8. **Broadcast (optional, later)** — announcements / segmented FCM push.
9. **Audit log & settings** — searchable action history; role assignment (super-admin only).

**How it's built:**
- Reuses the **Phase 8 Firestore data model** (users, pets, bookings, homestays, posts, chats, reviews) + the new admin collections above.
- A shared **Cloud Functions** layer for privileged ops (`setRole`, `verifyPartner`, `moderateContent`, `suspendUser`, `refundBooking`) — some reused by the mobile app.
- Built module-by-module, **launch-critical first** (verification → moderation → users), each behind the RBAC + audit-log spine.

**Verify:** a `moderator`-claim admin actions a reported post → change reflects in the app + an audit entry is written; a non-admin/insufficient-role is denied; approving a pro-verification flips the pro to `verified` and they appear in Services; a refund issued from admin flows through the Cloud Function and updates the booking.

**Dedicated spec:** before building, this phase gets its own `docs/superpowers/specs/` + plan defining exact Firestore collections/fields, Cloud Function signatures, and the RBAC matrix.

---

## Global verification & workflow

- Per task: `flutter analyze` clean + `flutter test` green, then commit.
- Per phase: run on the Android emulator (`flutter run -d emulator-5554`) and **compare each screen against `design/Pawgo Prototype.dc.html`** (open in a browser) — note drift as polish items, don't block on pixels.
- Firebase-backed work (Phase 2R onward): unit/widget tests use in-memory fakes behind the repository interfaces (no network); use the Firebase Local Emulator Suite where integration testing is useful.
- Each pillar phase (3–7) gets its own detailed `docs/superpowers/plans/` task file, following the Slice-1 plan's pattern, before implementation.

## Suggested sequencing note

**Revised (2026-07-08):** Slice 1 (Phases 1–2) delivered the design system + onboarding/auth/Home UI. Rather than finishing all 30 screens as static mocks first, the app **goes real now** (Phase 2R: auth + Firestore), and each remaining pillar (Phases 3–7) is built directly on that live backend — the owner wants a real app, not a static reproduction. Maps (Phase 9) and payments (Phase 10) remain the only deferred integrations and are wired when their pillars need them. **Phase 12 (Admin panel) is a parallel web-app workstream** — it can begin once the Phase 2R data model exists (users/pets), expanding as later pillars add collections; its verification + moderation + user-management modules must be live before the Phase 11 launch.
