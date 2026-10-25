# Plan — Pet Behaviourist + Home Brands

Spec: `docs/superpowers/specs/2026-10-25-pawgo-behaviourist-home-brands-design.md`.
TDD: each step lands with its tests; `flutter analyze` + `flutter test` +
`npm --prefix functions test` green before commit.

## A. Pet Behaviourist

1. `ServiceType.behaviourist` + `Specialty` enum + `Pro.specialties`
   (toMap/fromMap, unknown keys dropped). Serialization tests.
2. Pro setup: specialty chips shown only for Behaviourist; cleared when another
   type is saved. Widget test.
3. Pro card + pro profile show specialty tags when present. Widget test.
4. Services list: categories as a 3 × 2 grid (6 tiles incl. Home Brands);
   subtitle "Walkers, sitters, groomers, trainers & more". Widget test.
5. Functions `SERVICE_LABEL.behaviourist = "Pet Behaviourist"`. Catalog test.

## B. Home Brands — data + backend

6. `Brand`, `BrandProduct`, `BrandCategory`, `BrandDelivery` models
   (`lib/data/models/brand.dart`), `fromPrice`, max 10 products. Tests.
7. `BrandRepository` interface + `FirestoreBrandRepository` + providers
   (`brandsProvider` with block filter, `currentBrandProvider`) +
   `InMemoryBrandRepository` fake + pumpPgApp default.
8. `Role.brand` ("Home Brand"); `VerificationKind.brand`;
   `ReportTargetType.brand`.
9. `firestore.rules` `brands/{uid}` (owner write, `verified` server-owned,
   logo + ≤10 product photos must be ours); `storage.rules` `brands/{uid}/{file}`.
10. Functions: moderation path + uploader for `brands/`, deletion prefix
    `brands/{uid}/` and `brands/{uid}` doc in `deleteMyAccount`. Tests.
11. Admin: verification kind `brand` → `brands` collection, label "Home brand".

## C. Home Brands — screens

12. Services: Home Brands tile shows category chips + brand cards
    ("from ₹X", View); empty state.
13. `BrandProfileScreen` (`/brand`): header, logo card, facts row (delivery,
    since, products), about, product grid, report sheet, bottom bar
    chat + "Message to order".
14. `BrandSetupScreen` (`/brand-setup`): name, category, delivery, since year,
    about, logo, product editor (add/edit/remove, photo + name + price),
    verification card; validation; back-guard when dirty.
15. Sign-up role "Home Brand" → location → brand setup. Profile sheet gets
    "List your brand"; Services banner "Set up your brand" for brand role
    without a listing.

## D. Copy + docs

16. Website: services copy mentions behaviourists; terms + refunds +
    privacy cover Home Brands (orders arranged in chat, Pawgo not a party,
    FSSAI/legal compliance on the brand, no Pawgo refunds for brand orders).
17. CLAUDE.md / plan.md / launch checklist: new deploy needed
    (functions + firestore rules + storage rules).

## E. Verify

18. `flutter analyze`, `flutter test`, `npm --prefix functions test` + build,
    admin `npm run build`, debug APK on the emulator (owner deploys rules +
    functions first — the app can't write `brands/` until rules are live).
