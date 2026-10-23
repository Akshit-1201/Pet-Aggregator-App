# Pawgo Pets website — `pawgo-pets.web.app`

The public site Razorpay needs before it issues live API keys, and the home of
the privacy policy, terms and account-deletion page used by the app and both
app stores. Plain HTML + one stylesheet — no build step. Served by Firebase
Hosting from `website/public/` (config: `hosting` in `/firebase.json`).

Plan and background: `docs/website-and-razorpay-live-plan.md`.

| Page | URL |
|---|---|
| Home (incl. pricing) | `/` · `/#pricing` |
| Privacy policy | `/privacy` |
| Terms & conditions | `/terms` |
| Cancellation & refunds | `/refunds` |
| Service delivery | `/delivery` |
| Delete your account | `/delete-account` |
| Contact us | `/contact` |

## 1. Fill in the business details (required)

Six details only the client can provide appear as `[[PLACEHOLDERS]]`. **The
deploy refuses to run while any remain** (`check-placeholders.mjs` runs as a
predeploy step), so a half-filled site can't go live.

| Placeholder | What to put | Notes |
|---|---|---|
| `[[LEGAL_ENTITY]]` | Registered business name | **Must match the Razorpay KYC exactly.** The Razorpay account shows "Experimental Much" — confirm the exact legal name and suffix (e.g. Pvt Ltd / LLP / proprietorship) |
| `[[REGISTERED_ADDRESS]]` | Registered business address | Full postal address, as on the KYC |
| `[[SUPPORT_EMAIL]]` | Support email | Ideally on your own domain later; any monitored inbox works now |
| `[[SUPPORT_PHONE]]` | Support phone number | With +91 |
| `[[SUPPORT_HOURS]]` | When the phone is answered | e.g. "Mon–Sat, 10 am–7 pm IST" |
| `[[GRIEVANCE_OFFICER]]` | Name (and title) of the grievance officer | Required for the privacy policy under Indian IT rules |

Easiest: send the six values to Claude and it fills them in. Manually: in VS
Code, Find & Replace in Files (Ctrl+Shift+H), "files to include":
`website/public`, replace each placeholder everywhere. Then check:

```bash
node website/check-placeholders.mjs     # ✓ No placeholders left
```

## 2. Have the policy text reviewed

The pages are written from what the app actually does (fees, refund rules and
data handling were checked against the code on 2026-10-24), but they are not
legal advice. Get them reviewed. These **business commitments** in the copy
need the client's explicit OK:

- Full refund when a pro or host cancels or doesn't turn up (`/refunds`).
- Email replies within 2 working days (`/contact`); data-rights requests within
  30 days (`/privacy`); deletion-by-email within 30 days (`/delete-account`).
- Users must be 18+ (`/terms`, `/privacy`).
- Disputes under Mumbai courts (`/terms`).

If a fee or refund rule changes in the app, update `/refunds` and the pricing
section of `/` in the same change.

## 3. Preview locally

```bash
firebase emulators:start --only hosting --project demo-pawgo-site
# → http://127.0.0.1:5000  (clean URLs work exactly as in production)
```

## 4. Deploy to `pawgo-pets.web.app`

Prerequisites (client project): your Google account has access to `pawgo-pets`,
and Firebase Console → **Build → Hosting → Get started** has been clicked
through once. Hosting is free on the Spark plan — no billing needed for this.

```bash
firebase deploy --only hosting --project pawgo-pets
```

Always pass `--project pawgo-pets` — without it the CLI uses its current
project (`pet-aggregator-app`), and the site would go to
`pet-aggregator-app.web.app` instead.

## 5. Use the URLs

- **Razorpay:** Account & Settings → Websites & API keys → **+ Add website/app**
  → `https://pawgo-pets.web.app`. Approval takes 24–48 h, then Generate Key.
- **App:** paste `https://pawgo-pets.web.app/privacy` and
  `https://pawgo-pets.web.app/terms` into `lib/core/legal/legal_links.dart`.
- **Play Console:** privacy policy `/privacy`; account deletion `/delete-account`.
- **App Store Connect:** privacy policy `/privacy`; support URL `/contact`.
