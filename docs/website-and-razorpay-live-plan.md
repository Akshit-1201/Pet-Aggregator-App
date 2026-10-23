# Plan — Pawgo Pets website, legal pages, and going live on Razorpay

_Written 2026-10-24. Parked for later — nothing here is started._

## Why this is blocking

Razorpay won't issue **live API keys** until it approves a **live website or
app** for the business (Dashboard → Account & Settings → Websites & API keys →
"Generate Key" stays greyed out; review takes 24–48 h). The app isn't on Play
yet, so we need a small public website. The same site also unblocks:

| Needs the site | For what |
|---|---|
| Razorpay | Website approval → live API keys |
| Google Play | Privacy policy URL + account-deletion request URL (listing requirements) |
| App Store | Privacy policy URL + support URL (App Store Connect) |
| The app itself | The two URLs in `lib/core/legal/legal_links.dart` (in-app viewer is already built) |
| Email (Resend) | A domain we own, to send receipts from (`MAIL_FROM` is still `receipts@pawgo.app`) |

One site, built once, covers all five.

## 1. Decide the domain

- **Recommended:** buy a domain, e.g. `pawgopets.com` / `pawgopets.in`
  (~₹800–1,200/yr). Looks credible to Razorpay and the stores, and gives Resend
  a sending domain (`receipts@pawgopets.com`).
- **Free fallback:** Firebase Hosting on the existing project →
  `https://pet-aggregator-app.web.app`. Works immediately; a custom domain can
  be attached later without changing the hosting.

## 2. Host it — Firebase Hosting (recommended)

Already in this project, free at this size, HTTPS automatic. Plan:

- Add a `website/` folder (plain HTML + CSS, styled with the app's palette:
  brand `#F59E2E`, cream `#FBF1E8`, Poppins + Inter).
- Add a `hosting` block to `firebase.json` pointing at `website/`.
- Deploy: `firebase deploy --only hosting --project pet-aggregator-app`.
- Custom domain: Firebase Console → Hosting → Add custom domain → add the DNS
  records it shows at the domain registrar.

(Alternatives if preferred: GitHub Pages from this repo, or Google Sites — no
code, but less control over the policy pages' URLs.)

## 3. Pages to build

Razorpay's reviewer checks that these exist, are reachable from the home page
footer, and name the **same business as the Razorpay KYC**.

> ⚠️ **Business name must match KYC.** The Razorpay account is registered as
> **"Experimental Much"**. Every page footer should say
> "Pawgo Pets is operated by Experimental Much" with the registered address —
> a brand/KYC mismatch is a common rejection reason.

| Page | URL | Must contain |
|---|---|---|
| Home | `/` | What Pawgo Pets is (4 pillars), that it's for Mumbai, app download links ("coming soon" until live), pricing summary, footer links to every page below |
| Privacy Policy | `/privacy` | Built from the data inventory in `docs/launch-checklist.md` §8 (verified against the code). Also used in-app and in both stores |
| Terms & Conditions | `/terms` | Marketplace role (Pawgo connects parents with independent pros/hosts), accounts, acceptable use, moderation/blocking, payments via Razorpay, partner payouts, liability, governing law (India) |
| Cancellation & Refund Policy | `/refunds` | Exactly the rules in the code — see below |
| Pricing | on Home or `/pricing` | Fees — see below |
| Contact Us | `/contact` | Legal business name, registered address, support email, phone, support hours |
| Account deletion | `/delete-account` | Play requirement: how to delete in-app (Settings → Delete account), what is deleted vs kept, and an email route for people without the app |
| Shipping / Delivery (services) | `/delivery` | Razorpay sometimes asks even for services: "services are delivered in person at the booked date/time; no physical goods are shipped" |

**Refund policy — must match the code exactly** (`functions/src/index.ts`,
`lib/data/models/refund_policy.dart`):

- **Services** (walkers, sitters, groomers, trainers): full refund of the
  service rate if cancelled **before the day of the service**; no refund on or
  after that day.
- **Homestay**: full refund of the stay (nightly price × nights) if cancelled
  **at least 24 hours before check-in**; no refund after that. A request the
  host hasn't accepted yet can be withdrawn at no cost (nothing was paid).
- **Pawgo service fee is never refunded** — except when the failure is ours
  (e.g. the booked slot was lost while you were paying): then the whole amount,
  fee included, is refunded automatically.
- Refunds go back to the original payment method via Razorpay; banks take
  ~5–7 working days (UPI usually faster).

**Fees** (`functions/src/index.ts`):

- Services: Pawgo service fee = **10% of the rate** (e.g. ₹100 walk → ₹10 fee,
  ₹110 total).
- Homestay: flat **₹150** service fee per booking.
- Partners receive the rate / stay price; payouts are released the day after
  the booking completes (via Razorpay Route).

**Policy text:** draft it from the facts above, then have it reviewed by a
lawyer or a reputable generator — this plan deliberately doesn't contain legal
wording.

## 4. After the site is live

1. **Razorpay:** Account & Settings → Websites & API keys → **+ Add
   website/app** → the site URL. Wait 24–48 h for approval.
2. **Live keys:** once approved → **Generate Key** → save Key ID + Secret in a
   password manager (secret is shown once).
3. **Switch the backend** — in your own terminal, never pasted into chat:
   ```
   firebase functions:secrets:set RAZORPAY_KEY_ID --project pet-aggregator-app
   firebase functions:secrets:set RAZORPAY_KEY_SECRET --project pet-aggregator-app
   firebase deploy --only functions --project pet-aggregator-app
   ```
   No app build needed — the app gets the key from the server per order.
4. **Prove it:** ₹1 walker listing on your own account → pay with your own UPI
   → check Razorpay Dashboard (Live → Payments) → cancel → confirm the refund.
5. **Route:** ask Razorpay to activate **Route** (partner payouts) on the live
   account. Until then earnings wait safely as `owed`.
6. **In-app links:** paste `https://<domain>/privacy` and `/terms` into
   `lib/core/legal/legal_links.dart`, ship a build.
7. **Stores:** use `/privacy`, `/delete-account` and `/contact` in the Play
   listing and App Store Connect.
8. **Email:** verify the domain in Resend, set `RESEND_API_KEY`, change
   `MAIL_FROM` in `functions/src/notify/email.ts`, redeploy — customers then get
   receipts and refund emails (currently none are sent).

**Rollback** for step 3: set the two secrets back to the test values and
redeploy.

## What Claude can do when we pick this up

- Build the whole `website/` folder (all pages, app styling, mobile-friendly)
  and the `firebase.json` hosting config, with the fee/refund facts above.
- Draft every policy page from the code-verified facts, for review.
- Wire the URLs into the app and run the in-app viewer check on the emulator.
- After you deploy the live keys: confirm the live key id is in use (prefix
  only) and update `docs/launch-checklist.md`.

Owner-only: buying the domain + DNS, the Razorpay submission, generating and
storing keys, legal review of the policy text.
