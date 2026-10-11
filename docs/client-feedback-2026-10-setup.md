# Client feedback round (Oct 2026) — what shipped, and what you must switch on

The code for every item is in the repo and tested (471 Flutter tests, 101
Functions tests). Several items only go **live** after the console steps
below. Do them in order.

## 1. Deploy the backend

```bash
firebase deploy --only functions,firestore:rules
```

New Functions: `holdServiceSlot`, `releaseCancelledServiceSlot`,
`sendVerificationEmail`, `moderateUploadedImage`. Changed: `createBookingOrder`,
`verifyBookingPayment`. New rule: `proSchedule/{id}` (read-only for users).

**If the deploy rejects `moderateUploadedImage` with a location error:** a
Storage trigger must run in the same region as the bucket. The code assumes
`asia-south1`. Check the bucket's location in Firebase Console → Storage and
change `region` in `functions/src/moderation.ts` to match.

Deploy **before** shipping the new app build: the new booking screen calls
`holdServiceSlot`. (It degrades safely if the Function is missing, but the
early "someone just booked this" warning won't work until it's deployed.)

## 2. Google sign-in

1. Firebase Console → Authentication → Sign-in method → **enable Google**.
2. **Android only** — register SHA-1 fingerprints for `com.pawgopets.app`
   (Project settings → Your apps → Android → Add fingerprint):
   - release: `48:31:E5:13:AA:ED:B2:4F:2E:BB:F2:30:05:BD:38:05:53:20:96:9B`
   - each dev machine's debug key:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   - once on Play: the **Play App Signing** SHA-1 from Play Console.
3. Re-download `android/app/google-services.json` and commit it.

Until step 2, Android's "Continue with Google" shows *"Google sign-in isn't
available yet"*. iOS needs no extra step — its config was already present.

## 3. Sign in with Apple (iOS) — do this BEFORE the next iOS build

App Store guideline 4.8 requires it whenever Google login is offered.

1. developer.apple.com → Identifiers → `com.pawgopets.app` → enable
   **Sign In with Apple** → Save. Apple invalidates the existing App Store
   provisioning profile when you do this.
2. Delete that invalidated profile (Profiles) so Codemagic's
   `fetch-signing-files --create` generates a fresh one that includes the
   capability.
3. Firebase Console → Authentication → Sign-in method → **enable Apple**
   (native iOS needs no Services ID).

⚠️ The repo now contains `ios/Runner/Runner.entitlements` with the Apple
sign-in entitlement. **If you build iOS before step 1, signing fails** with a
"provisioning profile doesn't include com.apple.developer.applesignin" error.

## 4. Image moderation

Google Cloud Console (project `pet-aggregator-app`) → APIs & Services →
**Enable "Cloud Vision API"**. Billing is already on; the first 1,000 images a
month are free.

Until enabled, moderation **fails open**: uploads keep working and the Function
logs an error. Flagged photos are deleted and recorded in the
`moderationFlags` Firestore collection for review.

## 5. Branded verification email

Still gated on `RESEND_API_KEY` (currently the placeholder `unset`). Until it
is set, the app falls back to Firebase's own email — so verification always
works, but the branded "Verify my email" button only appears once Resend is
configured and `MAIL_FROM`'s domain is verified there.

## 6. Maps on Android

The "Pawgo Android Maps" key in Cloud Console must allow package
`com.pawgopets.app` (it still names the old package). Not a crash — blank tiles.

---

## Item-by-item

| Feedback | Root cause | Fix |
|---|---|---|
| Gmail / routed logins | Not built | Google (Android + iOS) and Apple (iOS) sign-in; new users finish setup with name prefilled, no password, no email step. Passwordless accounts can still delete themselves (re-confirm via Google/Apple). |
| Verification link is text | Firebase's locked template shows the raw URL and often lands in spam (Gmail disables links there) | Branded HTML email with a real button via `sendVerificationEmail` (falls back to Firebase's); spam-folder hint on the confirm screen |
| Image moderation | Not built | Cloud Vision SafeSearch on every public upload |
| My bookings / My homestays identical | For a parent both rows opened the same list | Second row is now "Bookings received", shown only to pros/hosts |
| 👋 next to "Hey Aakarsh" | — | Removed |
| Two-paws button next to notifs | The avatar placeholder is 🐾 and wasn't tappable | Initial-letter avatar that opens Profile |
| See map crashes | iOS: `GMSServices.provideAPIKey` was skipped while the key was a placeholder → hard crash on any map (Android verified not crashing on a device) | Always called. **Confirm with a TestFlight crash log if it persists** |
| Profile photos slow | No disk cache; avatars uploaded at 1080px | Disk-cached images everywhere; avatars upload at 512px |
| Home back button does nothing | It's "exit app", impossible on iOS | Removed from Home; exit-only chevrons hidden on iOS (Welcome, Location) |
| X on Discover acts like undo | Buttons swapped cards instantly (photo-less pets look identical), and the deck could include already-swiped pets | Buttons fly the card off like a swipe; deck waits for swipe history |
| Walker profile top buttons unresponsive | **Not reproduced** on Android with real touches | Header sized from the device safe area defensively. **Need a screen recording from the client's iPhone** |
| Message button doesn't work | Errors were swallowed silently; works with test data on a device | Failures now shown; self-chat and double-tap guarded |
| Dynamic time slots (owner) | 3 hard-coded times | Pro sets weekly hours + slot length; parents pick live free slots for 14 days; overlap impossible server-side (transactional per-pro-day schedule, 20-min payment hold, auto-refund if a hold is lost mid-payment) |
