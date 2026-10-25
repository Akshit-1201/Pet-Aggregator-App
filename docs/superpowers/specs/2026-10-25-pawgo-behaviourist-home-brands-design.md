# Pet Behaviourist + Home Brands in Services — design

Status: approved by the owner on 2026-10-25 from the mockup (four screens:
Services grid, Behaviourist list, Home Brands list, brand page). Plan:
`docs/superpowers/plans/2026-10-25-pawgo-behaviourist-home-brands.md`.

## Why

The client wants two more things under Services: **pet behaviourists** (a
professional who fixes anxiety, aggression, reactivity…) and **Home Brands**
(small, homegrown Mumbai pet businesses selling treats, food, accessories and
care products).

## Goals

1. **Pet Behaviourist** is a fifth kind of pro. Everything a pro already has
   (weekly hours, slot booking, Razorpay payment, refunds, payouts, reviews,
   chat, verification) works unchanged. New: unit "consult", optional
   **specialty tags** chosen from a fixed list, shown on the card and profile.
2. **Home Brands** is a new listing type and a new sign-up role ("Home Brand").
   A brand has a name, category, delivery area, optional "since" year, about,
   logo and 1–10 products (photo, name, price). Parents browse brands in
   Services → Home Brands, open a brand page and **order by chat**.
3. Services' category row becomes a **3 × 2 grid** (six categories).

## Non-goals (v1)

- No in-app checkout for brands: no cart, Razorpay, delivery tracking, returns
  or fees. Pawgo is not a party to the sale (terms say so).
- No brand reviews/ratings — reviews are tied to paid bookings, which brands
  don't have. Brand cards show the verified badge instead of stars.
- No brands on the Nearby map.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Behaviourist storage key | `behaviourist`, label "Pet Behaviourist", 🧠, unit `consult`, verb `assess` | Matches the `ServiceType` enum shape |
| Specialties | Fixed enum (`Specialty`), stored as keys on `pros/{uid}.specialties`; only offered/saved for behaviourists | Fixed list = no free-text moderation; unknown keys dropped on read |
| Brand data | One doc `brands/{uid}`; products as an array (max 10) inside it | One read per brand, atomic save, deletion is one doc; rules can check each product photo |
| Brand photos | Storage `brands/{uid}/…` — owner-only write, signed-in read, image ≤ 5 MB | Same as homestay photos; moderated by `moderateUploadedImage` |
| Server-owned brand fields | `verified` only | No ratings for brands in v1 |
| Verification | New `VerificationKind.brand`; admin approval sets `brands/{uid}.verified` | Reuses KYC flow |
| Reports | New `ReportTargetType.brand` ("listing") | Play UGC policy |
| Account deletion | Deletes `brands/{uid}` and Storage `brands/{uid}/` | Personal data dies with the account |
| Brand listing order | `updatedAt` desc, blocked owners filtered | Same as pros/homestays |
| Where brands load | Only when the Home Brands category is selected | "Recommended" stays pros-only |

## Known limitations

- Chat masks phone numbers, so brand and buyer arrange address and payment
  (UPI ID / cash on delivery) in chat without exchanging numbers.
- The `isOurPhoto` rule pins the `pet-aggregator-app` bucket, like every other
  photo (tracked in the client-project migration plan).
- Food sellers need FSSAI registration; the terms make that the brand's
  responsibility. The app does not collect licence numbers in v1.
