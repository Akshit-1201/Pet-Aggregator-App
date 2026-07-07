# Pawgo — Foundation + Onboarding/Auth (Design Spec)

**Date:** 2026-07-07
**Status:** Draft for review
**Slice:** 1 of N (first of the phased port of the Pawgo prototype)
**Stack:** Flutter (Android, Mumbai market) + Firebase (wired in a later slice)
**Source of truth:** `design/Pawgo Prototype.dc.html` (imported from the claude.ai design project)

---

## 1. Purpose & context

We are porting an existing, complete 30-screen prototype ("Pawgo") into the Flutter app **faithfully** — matching its colours, typography, spacing and layout. Because 30 screens is far too large for one plan, we build in slices. Chosen strategy: **design system → static UI → wire backend.**

This spec covers **Slice 1: the Foundation + the Onboarding/Auth flow**, ending on a static Home feed. It establishes the theme, shared widgets, navigation and folder structure that every later slice reuses.

Everything in this slice is **static UI with mock data** — no Firebase calls yet. The Firebase packages are already installed and initialised (`main.dart`), but wiring is a later slice.

## 2. Full screen map (for context, not all built here)

30 screens grouped by pillar. Slice numbers are the proposed build order.

| Pillar | Screens | Slice |
|---|---|---|
| **Foundation + Onboarding/Auth** | Splash, Onboarding ×4, Welcome/Login, Sign-up+Role, Location, Create Pet | **1 (this spec)** |
| **Discovery ("Woof")** | Home Feed, Discover (swipe deck), Woof Match, Nearby Map, Pet Profile | 2 |
| **Services** | Services List, Pro Profile, Booking, Payment, Booking Confirmed | 3 |
| **Homestay** | Homestay List, Host Profile, Homestay Request, Host Accepted | 4 |
| **Community** | Community Feed, New Post, Thread Detail, Post Live | 5 |
| **Shared** | Chat List, Chat Conversation, Notifications, Profile, Settings, Rate & Review | 6 |

> Note: The Home feed is built (static) in this slice as the landing screen and the app shell's first tab. The other bottom-nav tabs (Discover, Services, Community, Profile) are placeholder screens until their slices.

## 3. Architecture

| Concern | Choice |
|---|---|
| Navigation | `go_router`. Splash, Onboarding, Welcome/Login, Sign-up, Location and Create Pet are **full-screen routes** (no bottom nav). Home and the other tabs live inside a `StatefulShellRoute` that renders the persistent `PgBottomNav`. |
| State management | `flutter_riverpod` (minimal use in the static phase; carries the backend-wiring phase) |
| Fonts | `google_fonts` — Poppins (headings/buttons) + Inter (body); bundled for offline/exact rendering |
| Structure | Feature-first |

**New packages this slice:** `go_router`, `flutter_riverpod`, `google_fonts`.

**Folder structure:**
```
lib/
  main.dart                 // Firebase init (done) + runApp(ProviderScope(...))
  app.dart                  // MaterialApp.router; theme + router
  core/
    theme/
      app_colors.dart       // PgColors: light + dark token sets
      app_typography.dart   // PgText: Poppins/Inter TextStyles
      app_spacing.dart      // radii, spacing, shadows
      app_theme.dart        // ThemeData light() / dark()
    widgets/                // shared: PgPrimaryButton, PgGhostButton, PgTextField,
                            //         PgChoiceCard, PgToggle, PgPageDots, PgChip,
                            //         PgAppBar, PgBottomNav, PgScreenScaffold
    router/
      app_router.dart       // routes + shell
      routes.dart           // route-name constants
  features/
    onboarding/             // splash_screen, onboarding_screen (data-driven ×4)
    auth/                   // welcome_screen, signup_screen, location_screen
    pets/                   // create_pet_screen
    home/                   // home_screen (static feed) + shell placeholders
  data/
    models/                 // PetProfile, UserProfile, Role
    mock/                   // mock_pets.dart, mock_user.dart
    repositories/           // abstract PetRepository, AuthRepository (+ mock impls)
```

**Intentional deviation:** the prototype renders inside a browser **phone-frame** (rounded bezel, notch, side menu). Those are preview chrome — the real app fills the device, so we drop them and keep only the screen content. The status-bar row (9:41 + signal/battery icons) is also dropped; the real OS status bar takes its place (we keep the top safe-area padding).

## 4. Design system (exact tokens from the file)

### 4.1 Colours

**Light theme**
| Token | Hex | | Token | Hex |
|---|---|---|---|---|
| bg | `#FBF1E8` | | brand | `#F59E2E` |
| surface | `#FFFFFF` | | brand2 | `#F0871E` |
| surface2 | `#FBEDE1` | | brandDeep | `#E07712` |
| text | `#1F1A17` | | brandSoft | `#FCE7CC` |
| muted | `#8A7F77` | | ink | `#211B17` |
| faint | `#B7ACA2` | | heart | `#EF4B5E` |
| border | `#F1E5D8` | | blue | `#6B8DE0` |

Accent surfaces: peach `#F4C9B6`, lav `#E7DBF7`, butter `#FBE7B0`, mint `#CFEBD9`, purple `#B79BE8`, pink `#EC8FB0`.

**Dark theme**
| Token | Hex | | Token | Hex |
|---|---|---|---|---|
| bg | `#1A1410` | | text | `#F7EFE7` |
| surface | `#241C16` | | muted | `#B6A99C` |
| surface2 | `#2F251D` | | faint | `#857667` |
| border | `#3A2E24` | | brandSoft | `#3D2A12` |

Brand amber stays constant across themes. Accent surfaces darken: peach `#5A3D2C`, lav `#352A47`, butter `#403517`, mint `#1E3A2C`.

**Shadows:** `shadow` = light `0 12px 32px rgba(120,72,30,.12)` / dark `0 14px 36px rgba(0,0,0,.55)`; `shadowSm` = light `0 5px 16px rgba(120,72,30,.08)` / dark `0 5px 18px rgba(0,0,0,.45)`. Brand glow (primary buttons) ≈ `0 14px 30px rgba(245,158,46,.25)`.

### 4.2 Typography

- **Poppins** (500/600/700/800): logo, screen titles, section headers, button labels.
- **Inter** (400/500/600/700): body copy, field labels, secondary text.
- Scale: splash 34/800 · welcome 30/800 · screen title 24–27/800 · section header 16/700 · card title 14.5–15/700 · body 14.5/400-500 · label 12.5/600 · caption 11–12. Large Poppins headings use `letter-spacing: -0.4…-0.5`.

### 4.3 Radii & spacing

- Radii: primary button **16–17**, inputs **14–15**, cards **18**, big illustration/deck cards **28–30**, pills/chips **20–30**, small icon buttons **12–13**, bottom sheets **26–32** (top corners).
- Screen content padding ≈ 22–30px horizontal; top safe padding ≈ 54px (below status bar).

### 4.4 Shared widgets built this slice

- **PgPrimaryButton** — gradient `linear-gradient(135°, brand→brand2)`, Poppins 700 ~15.5px, white, radius 16, brand glow shadow, `scale(.95)` tap feedback.
- **PgGhostButton / PgTextButton** — transparent, muted text (Skip / "Set location manually").
- **PgTextField** — surface2 fill, 1px border, radius 14, label above (Inter 12.5/600). (Display-only in this slice; real inputs when wired.)
- **PgChoiceCard** — selectable row/tile with icon + title + subtitle + check indicator; selected state = 2px brand border on `brandSoft`. Used for role select and species select.
- **PgToggle** — pill switch (46×27, brand when on) for "Vaccinated".
- **PgPageDots** — onboarding indicator; active dot is a 24px-wide brand bar, inactive 7px border dots.
- **PgChip / PgTag** — category pill (e.g. "Health", filter chips).
- **PgAppBar** — back chevron button (42×42 bordered) + Poppins 700 title.
- **PgBottomNav** — persistent 5-tab bar (exact icons/labels taken from the prototype's "bottom nav" block at build time).
- **PgScreenScaffold** — themed background + safe-area handling wrapper.

## 5. Screens in this slice

All navigation targets below are as wired in the prototype's `onClick` handlers.

1. **Splash** — amber gradient (`#F8B45E→#F0871E→#E07712`), centred rounded-square logo with animated pulse ring, "Pawgo" (Poppins 800/34) + tagline "Your pet's whole world, nearby", bouncing dots. Auto-advances to Onboarding 1.
2. **Onboarding 1–4** — one data-driven screen rendered 4×. Layout: 460px illustration header (per-page gradient + floating rotated photo card) over content (Poppins 800/27 title, Inter 14.5 muted body, PgPageDots, Skip + Next; screen 4 shows a full-width "Get started"). Copy/gradients per page:
   - 1 Find playmates (amber/cream) · 2 Trusted walkers, sitters & groomers (mint) · 3 Homestays with verified hosts (lavender) · 4 A community that has your back (blue).
   - Skip → Welcome; Next → next page; Get started → Welcome.
3. **Welcome / Login** — amber gradient top with logo + "Welcome back 👋"; white rounded-top sheet with phone field, password field (+ "Forgot?"), **Log in** (→ Home), "or continue with" divider, Google/Apple buttons, "Create account" (→ Sign-up).
4. **Sign-up + Role** — PgAppBar "Create account"; fields (Full name, Mobile, Password); "I'M JOINING AS" with 3 PgChoiceCards (**Pet Parent** selected by default, Service Professional, Homestay Host — "needs verification"); sticky **Continue** (→ Location).
5. **Location permission** — centred illustration (pin + radar rings), "Enable location", copy stressing **approximate area only, never exact address**; **Allow while using app** and **Set location manually** (both → Create Pet).
6. **Create Pet** — PgAppBar "Add your pet"; circular photo upload; Pet name; Breed + Age row; **Species** segmented (Dog/Cat/Other, Dog selected); **Vaccinated** toggle (on); sticky **Finish & explore Pawgo** (→ Home).
7. **Home feed (static landing)** — header (📍 Bandra West, Mumbai · "Hey Radhika 👋" · "6 pets near you today" · bell + avatar); 2×2 quick-action grid (Discover/Services/Homestay/Community with the prototype's accent colours); "Pets near you" list (PetRow + Woof! button, from mock data) with "See map →"; "Community picks" card. Includes the shimmer skeleton loading state. Sits inside the app shell with the persistent bottom nav; the other tabs are placeholders this slice.

## 6. Data & mock strategy

- **Models** (plain Dart, immutable): `UserProfile { name, phone, role, area }`, `PetProfile { name, species, breed, ageLabel, vaccinated, distanceLabel, photoUrl?, accentColor }`, `enum Role { petParent, servicePro, homestayHost }`.
- **Repositories** are abstract interfaces (`AuthRepository`, `PetRepository`) with **mock implementations** returning hard-coded prototype data (Bruno/Labrador, Mochi/Persian, etc.). Riverpod providers expose them.
- **Wiring later:** the Firebase-backed implementations (FirebaseAuth, Firestore) implement the same interfaces and swap in at the provider layer — screens don't change. This is the seam that makes "wire backend later" clean.

## 7. Images / assets

- The prototype uses `<image-slot>` placeholders (user drops photos in). In Flutter these become `PgImageSlot` widgets: show a rounded placeholder (icon/emoji + soft bg) now, ready to accept a network/asset image later. No real photos are required for this slice.
- Fonts bundled under `assets/fonts/` (or fetched via `google_fonts`); declared in `pubspec.yaml`.

## 8. Testing

- Widget tests for each of the 7 screens: renders without error, key text present, primary button navigates to the correct route (using a test `GoRouter`).
- A theme test asserting light/dark `PgColors` resolve. Golden tests are optional (deferred — pixel goldens are brittle during active styling).

## 9. Fidelity approach & known deviations

- "Exact same design" = a faithful re-implementation, matched by eye against the prototype's rendered screens, iterating on spacing/colour. Not a pixel-identical export.
- Deviations (all intentional): phone-frame bezel/notch dropped; fake status bar dropped (real OS bar used); prototype's CSS animations reproduced with Flutter equivalents where cheap (splash pulse, page transitions) and simplified where costly.

## 10. Out of scope (this slice)

- All non-foundation pillars (Discovery interactions, Services, Homestay, Community, Chat, Notifications, Profile, Settings, Rate & Review).
- Any Firebase wiring (auth, Firestore, storage, messaging), Maps rendering, and payments.
- Real photo upload, OTP verification, form validation logic.

## 11. Open questions / assumptions

- **A1:** Login/OTP is visual-only this slice; real phone-OTP auth (incl. SHA fingerprints) lands in the wiring slice. (Assumed OK.)
- **A2:** Bottom-nav tab set assumed to be Home / Discover / Services / Community / Profile; exact icons/labels confirmed against the prototype's nav block at build time.
- **A3:** App defaults to **light** theme; dark theme fully defined and switchable, but no in-app theme toggle screen this slice (Settings is a later slice).
