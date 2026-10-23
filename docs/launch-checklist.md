# Pawgo Pets — launch checklist

_Written 2026-10-23 against `main` + the `phone-sign-in-launch-prep` branch._
This is the single list of what stands between the current build and a public
release. The app is feature-complete; almost everything left is a console,
account or store step only the owner can do. Items are in the order they should
happen — several later steps depend on earlier ones.

Legend: 👤 owner (console / account / store) · 💻 code change · ✅ already done

---

## 1. Deploy the backend — do this first

- [ ] 👤 `firebase deploy --only functions,firestore:rules`
  New/changed since the last deploy: `holdServiceSlot`,
  `releaseCancelledServiceSlot`, `sendVerificationEmail`,
  `moderateUploadedImage`, `createBookingOrder`, `verifyBookingPayment`, the
  email-**or-phone** verified check in slot holds, and `deleteMyAccount`
  (now also removes pet/homestay photos, KYC ID documents, push tokens, the
  block list and the verification request — previously left behind). **Must precede the next
  app build**, or phone users can't book services. If
  `moderateUploadedImage` fails with a location error, see
  `docs/client-feedback-2026-10-setup.md` §1.
- [ ] 👤 Confirm with `firebase functions:list` that the new names appear.
  (A brand-new event trigger sometimes fails once with an Eventarc permission
  error — retry the same deploy after a few minutes.)

## 2. Console switches

Details and exact values are in `docs/client-feedback-2026-10-setup.md`.

- [ ] 👤 **Authentication → Sign-in method:** enable **Google**, **Apple**,
  **Phone**. Then **Settings → SMS region policy → allow only India**.
- [ ] 👤 **Firebase → Android app → fingerprints:** release SHA-1 + SHA-256,
  each dev machine's debug SHA-1 + SHA-256 (values in the setup doc §2, §7).
  Re-download `android/app/google-services.json` and commit it.
- [ ] 👤 **Cloud Console → enable APIs:** Cloud Vision (image moderation),
  Play Integrity (phone auth + App Check).
- [ ] 👤 **"Pawgo Android Maps" key:** allow package `com.pawgopets.app`
  (it still names `com.pawgo.app` → blank map tiles).
- [ ] 👤 **Phone numbers for testing** (Auth → Phone): add one or two so QA
  never spends real SMS.

## 3. Content the stores require (nothing in the repo yet)

- [ ] 👤 **Privacy policy**, hosted at a public URL. Section 8 below lists
  every piece of data the app handles — hand it to whoever writes the policy.
- [ ] 👤 **Account-deletion web page.** Play requires a URL where someone can
  ask for deletion *without* the app installed. It can be a simple page with a
  support email; in-app deletion already exists (Settings → Delete account).
- [ ] 💻 **Link the privacy policy in the app** (Settings → ABOUT row, and
  under the sign-up form). Apple requires it in-app; Play recommends it.
  Blocked only on the URL — a ~20-line change once it exists.
- [ ] 👤 Support email address for the store listings.

## 4. Build and upload to Play (internal testing)

- [ ] 👤 Play Console: create the app `com.pawgopets.app`, opt into **Play
  App Signing**.
- [ ] 👤 Bump `version:` in `pubspec.yaml` for every upload (`1.0.0+1` now;
  the `+N` build number must increase each time).
- [ ] 👤 Build the bundle:
  ```bash
  rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
  flutter build appbundle --release
  ```
  (The `rm` avoids the stale-registrant gotcha in `CLAUDE.md`.) R8 is on;
  the bundle carries its own mapping file, so Play de-obfuscates crash
  stack traces automatically.
- [ ] 👤 Upload to the **internal testing** track.
- [ ] 👤 **Copy the Play App Signing SHA-1 + SHA-256** (Play Console → Setup →
  App signing) into **Firebase** (Android app fingerprints) **and** the
  **Maps key** restriction. Play re-signs the app with its own key, so without
  this, Google sign-in, phone sign-in and the map all fail on Play installs
  while working on sideloaded builds.
- [ ] 👤 Data-safety form (section 8), content rating questionnaire, target
  audience (not for children), store listing: name, short + full description,
  icon (`assets/icon/`), feature graphic, phone screenshots.

## 5. On-device pass on the Play-installed build

Run on a real phone with the internal-testing install, not a sideload.

- [ ] Sign up with email → verification link → lands in the app.
- [ ] Continue with Google; Continue with phone (use a test number).
- [ ] **Razorpay test payment end-to-end on the release build** — services
  book → pay → "Upcoming". This is the one R8-sensitive path not yet run on a
  release build (static checks pass: no Razorpay class renamed, payment
  callbacks kept). Domestic test card `5267 3181 8797 5449`, `12/30`, any CVV,
  OTP `1111` — the generic `4111…` card is rejected on this account.
- [ ] Homestay request → host accepts → guest pays → cancel ≥24h → refund.
- [ ] Map shows tiles (proves the Maps key change).
- [ ] Push arrives for a chat message (proves FCM tokens register).
- [ ] Photo upload; a flagged image is removed (proves Vision is on).
- [ ] Delete account for a password, a Google and a phone account.
- [ ] Back-navigation items never verified on hardware: the photo-form
  discard dialog, verify-email signing out, back during Razorpay verification.

## 6. Switch on the protections that need a released build

Only after testers have the Play build — each one breaks older builds or
real money paths if done earlier.

- [ ] 👤 **App Check:** register the Android app with Play Integrity (and iOS
  with App Attest), watch the App Check metrics until nearly all requests are
  verified, then set `ENFORCE_APP_CHECK = true` in `functions/src/index.ts`
  and redeploy Functions. Rollout order is documented above that constant.
- [ ] 👤 **Razorpay live keys:** `firebase functions:secrets:set
  RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`, redeploy Functions. Nothing in the
  app changes — the key id arrives per order.
- [ ] 👤 **Razorpay Route** activation for partner payouts. Until then payouts
  accrue as `owed` and retry nightly (by design).

## 7. Email, iOS and the admin panel

- [ ] 👤 **Email (Resend):** create an account, verify a sending domain, set
  `RESEND_API_KEY`, update `MAIL_FROM` in `functions/src/notify/email.ts`
  (currently `receipts@pawgo.app` — confirm that domain is owned), redeploy.
  Until then all 16 email scenarios are silently skipped and verification
  falls back to Firebase's plain email.
- [ ] 👤 **iOS** (`docs/pawgo-pets-rename-and-ios-setup.md`): enable **Sign In
  with Apple** on the App ID *before* the next Codemagic build (signing fails
  otherwise), upload the APNs `.p8` to Firebase, create the iOS Maps key and
  replace `REPLACE_WITH_IOS_MAPS_API_KEY` in `ios/Runner/AppDelegate.swift`,
  fill the App Store privacy "nutrition labels" from section 8.
- [ ] 👤 **Admin panel hosting:** choose Vercel or Firebase Hosting; run
  `npm audit` in `admin/` first (21 known advisories, mostly dev-only) since it
  would then be on the public internet. Bootstrap admins with
  `node admin/scripts/bootstrap-admin.mjs <email>`.

## 8. Data inventory (for the privacy policy, Play data-safety form and App Store labels)

Verified against the code on 2026-10-23. **The app contains no analytics,
crash-reporting or advertising SDK** and never reads device location (the
"area" is picked from a list).

| Data | Collected from | Stored in | Why | Shared with |
|---|---|---|---|---|
| Name, role, Mumbai area | Sign-up | Firestore `users` | Profile, matching, listings | Other users see name/area |
| Email address | Email or Google/Apple sign-in | Firebase Auth, `users` | Sign-in, receipts, notifications | Resend (email delivery) |
| Phone number | Phone sign-in | Firebase Auth only | Sign-in | Google (SMS delivery) |
| Pet details + photos | Create pet | Firestore `pets`, Cloud Storage | Discover, profiles | Public to app users; photos scanned by Google Cloud Vision |
| Avatar, post, homestay photos | Upload | Cloud Storage | Display | Public to app users; scanned by Cloud Vision |
| Chat messages | Chat | Firestore `chats` | Messaging | The other participant. Phone numbers, emails and URLs are masked server-side |
| Posts, comments, reviews | Community, reviews | Firestore | Forum, ratings | Public to app users; kept anonymised after account deletion |
| Bookings + payment records | Booking flow | Firestore `bookings`, `homestayBookings`, `payments` | Fulfilment, refunds, accounting | The pro/host; Razorpay. **Card/UPI details go only to Razorpay** — the app stores payment ids and amounts |
| Partner bank account + PAN | Earnings card | **Not stored** — passed straight to Razorpay; only account id, IFSC and masked last 4 kept | Payouts | Razorpay |
| ID documents (KYC) | Pro/host setup | Cloud Storage `verification/` — unreadable by any client | Partner verification | Pawgo staff via the admin panel (15-minute signed links) |
| Device push token | Automatic after sign-in | `users/{uid}/fcmTokens` | Push notifications | Google (FCM) |
| Device integrity attestation | Automatic | Not stored | Abuse prevention (App Check) | Google (Play Integrity / App Attest) |
| Reports and blocks | Report/block sheet | Firestore `reports`, `users/{uid}/blocked` | Moderation | Pawgo staff |

**Deletion:** in-app (Settings → Delete account) immediately deletes the
sign-in account, profile, pets, listings, swipes, notifications, push tokens,
block list, verification request, and the avatar, pet and homestay photos and
KYC ID documents in Storage. Posts, comments and reviews are kept but
anonymised (post photos stay with their posts). Bookings, payment records and
a partner's payout-account reference (Razorpay account id, IFSC, masked last 4)
are retained as financial records — the payout record is what lets earnings
still owed to a deleted partner reach them. There is no grace period.
