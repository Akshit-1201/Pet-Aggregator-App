import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as crypto from "crypto";
import Razorpay from "razorpay";
import * as admin from "firebase-admin";
import {sendInvoiceEmail, sendRefundEmail, InvoiceLine} from "./invoice";
import {recordPayoutOwed, reversePayout, type PayoutStatus} from "./payouts";
import {createLinkedAccount, readBankDetails, savePayoutAccount} from "./payout-account";
import {notify} from "./notify/notify";
import {bookingKey} from "./notify/keys";
import {maskContactDetails} from "./notify/mask";
import {MAIL_FROM} from "./notify/email";
export {maskContactDetails};

admin.initializeApp();

const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");
const resendApiKey = defineSecret("RESEND_API_KEY");

/** Receipts go to the address on the auth record, not to anything the client
 *  passed in — the client could send someone else's. Since signup now requires
 *  clicking a verification link, that address is also known to be real and
 *  owned by this user. */
async function verifiedEmailFor(uid: string): Promise<string> {
  try {
    const user = await admin.auth().getUser(uid);
    return user.emailVerified && user.email ? user.email : "";
  } catch (e) {
    logger.error("verifiedEmailFor failed", {uid, error: e});
    return "";
  }
}

type Kind = "service" | "homestay";

const REGION = "asia-south1";

/**
 * App Check enforcement on the callables.
 *
 * **Deliberately false.** Enforcement is server-side and takes effect the
 * instant this deploys: every build in the wild without an App Check token
 * starts failing at once — payments, refunds, account deletion, all of it. The
 * app only began sending tokens in the same change that added this flag, so
 * flipping it now would break every already-installed build, including the
 * owner's test devices.
 *
 * The rollout, in order:
 *   1. Ship a build that activates App Check (done — see lib/main.dart).
 *   2. Register the app for Play Integrity: Firebase Console → App Check, using
 *      `com.pawgo.app` and the release SHA-256 from android/app/pawgo-release.jks.
 *   3. Register a debug token for each dev machine/emulator, or local runs break.
 *   4. Turn on MONITORING (not enforcement) for Functions, Firestore, Storage.
 *   5. Watch the verified-request percentage until effectively all traffic is
 *      attested — i.e. old builds have aged out.
 *   6. Only then set this to true and redeploy.
 *
 * Skipping to step 6 is the failure mode Firebase's monitoring phase exists to
 * prevent.
 */
const ENFORCE_APP_CHECK = false;

/** Reads the booking, asserts ownership + payable state, and recomputes the
 *  authoritative price from the LISTING (never from client-written fields). */
async function loadPayable(kind: Kind, bookingId: string, uid: string) {
  const db = admin.firestore();
  const col = kind === "service" ? "bookings" : "homestayBookings";
  const ref = db.collection(col).doc(bookingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "no-booking");
  const b = snap.data() as FirebaseFirestore.DocumentData;

  const ownerField = kind === "service" ? "parentId" : "guestId";
  if (b[ownerField] !== uid) throw new HttpsError("permission-denied", "not-your-booking");
  const payableStatus = kind === "service" ? "pending" : "accepted";
  if (b.status !== payableStatus) throw new HttpsError("failed-precondition", "not-payable");

  let amounts: {total: number; parts: Record<string, number>};
  if (kind === "service") {
    const pro = await db.collection("pros").doc(String(b.proId)).get();
    if (!pro.exists) throw new HttpsError("failed-precondition", "no-listing");
    const rate = Number(pro.data()?.rate);
    if (!Number.isFinite(rate) || rate <= 0) throw new HttpsError("failed-precondition", "bad-amount");
    const fee = Math.round(rate * 0.1);
    amounts = {total: rate + fee, parts: {rate, fee, total: rate + fee}};
  } else {
    const home = await db.collection("homestays").doc(String(b.hostId)).get();
    if (!home.exists) throw new HttpsError("failed-precondition", "no-listing");
    const ratePerNight = Number(home.data()?.ratePerNight);
    // checkIn/checkOut are date-only YYYY-MM-DD at IST midnight (existing contract).
    const ci = new Date(`${String(b.checkIn).slice(0, 10)}T00:00:00+05:30`);
    const co = new Date(`${String(b.checkOut).slice(0, 10)}T00:00:00+05:30`);
    if (!Number.isFinite(ci.getTime()) || !Number.isFinite(co.getTime())) {
      throw new HttpsError("failed-precondition", "bad-amount");
    }
    const nights = Math.round((co.getTime() - ci.getTime()) / 86400000);
    if (!Number.isFinite(ratePerNight) || ratePerNight <= 0 || nights <= 0) {
      throw new HttpsError("failed-precondition", "bad-amount");
    }
    const subtotal = ratePerNight * nights;
    const fee = 150;
    amounts = {total: subtotal + fee, parts: {subtotal, fee, nights, total: subtotal + fee}};
  }
  if (amounts.total <= 0) throw new HttpsError("failed-precondition", "bad-amount");
  // Never surprise-charge: the stored total must match what the server computes.
  if (Number(b.total) !== amounts.total) {
    throw new HttpsError("failed-precondition", "amount-mismatch");
  }
  return {ref, booking: b, amounts};
}

function readArgs(data: unknown) {
  const d = (data ?? {}) as Record<string, unknown>;
  const kind = d.kind;
  const bookingId = d.bookingId;
  if ((kind !== "service" && kind !== "homestay") ||
      typeof bookingId !== "string" || bookingId === "") {
    throw new HttpsError("invalid-argument", "bad-args");
  }
  return {kind: kind as Kind, bookingId};
}

export const createBookingOrder = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK,
    secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const {kind, bookingId} = readArgs(request.data);
    const uid = request.auth.uid;
    const {amounts} = await loadPayable(kind, bookingId, uid);
    const rzp = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });
    try {
      const order = await rzp.orders.create({
        amount: amounts.total * 100, // paise — server-computed, never client-supplied
        currency: "INR",
        receipt: `bk_${uid}_${Date.now()}`.slice(0, 40),
        notes: {bookingId, kind, uid}, // binds this order to this booking
      });
      return {orderId: order.id, amountPaise: order.amount, keyId: razorpayKeyId.value()};
    } catch (e) {
      logger.error("createBookingOrder failed", e);
      throw new HttpsError("internal", "order-failed");
    }
  });

export const verifyBookingPayment = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK,
    secrets: [razorpayKeyId, razorpayKeySecret, resendApiKey]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const {kind, bookingId} = readArgs(request.data);
    const d = request.data as Record<string, unknown>;
    const {orderId, paymentId, signature} = d;
    if (typeof orderId !== "string" || orderId === "" ||
        typeof paymentId !== "string" || paymentId === "" ||
        typeof signature !== "string" || signature === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    const uid = request.auth.uid;

    // 1. The signature proves Razorpay issued this payment for this order.
    const expected = crypto.createHmac("sha256", razorpayKeySecret.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
    const a = Buffer.from(expected);
    const b = Buffer.from(signature);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      throw new HttpsError("permission-denied", "signature-mismatch");
    }

    // 2. The order's notes prove it was created for THIS booking and caller —
    //    without this a payment for booking A could confirm booking B.
    let order;
    try {
      const rzp = new Razorpay({
        key_id: razorpayKeyId.value(),
        key_secret: razorpayKeySecret.value(),
      });
      order = await rzp.orders.fetch(orderId);
    } catch (e) {
      logger.error("verifyBookingPayment order fetch failed", e);
      throw new HttpsError("internal", "order-fetch-failed");
    }
    const notes = (order?.notes ?? {}) as Record<string, unknown>;
    if (notes.bookingId !== bookingId || notes.kind !== kind || notes.uid !== uid) {
      throw new HttpsError("permission-denied", "order-booking-mismatch");
    }

    // 3. Re-validate (state may have changed since the order) and write.
    const {ref, amounts} = await loadPayable(kind, bookingId, uid);
    const payableStatus = kind === "service" ? "pending" : "accepted";
    const paidStatus = kind === "service" ? "confirmed" : "paid";
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "no-booking");
      if (snap.data()?.status !== payableStatus) {
        throw new HttpsError("failed-precondition", "not-payable");
      }
      tx.update(ref, {
        ...amounts.parts, // server-authoritative amounts
        status: paidStatus,
        paymentId,
        updatedAt: Date.now(),
      });
    });

    // What the partner is owed. Recorded here but NOT transferred here: every
    // Razorpay Route call happens later in processPayouts, so a disabled or
    // misconfigured Route can never make a customer's payment fail.
    try {
      const b = (await ref.get()).data() ?? {};
      await recordPayoutOwed({
        kind,
        bookingId,
        partnerId: String(kind === "service" ? b.proId ?? "" : b.hostId ?? ""),
        parts: amounts.parts,
        booking: b,
        paymentId,
      });
    } catch (e) {
      logger.error("verifyBookingPayment: payout record failed", {bookingId, error: e});
    }

    // Receipt. Awaited so a hard failure is visible in the logs, but never
    // allowed to throw — the money has moved and the booking is confirmed, so
    // a mail outage must not surface to the user as a failed payment.
    try {
      const b = (await ref.get()).data() ?? {};
      const to = await verifiedEmailFor(uid);
      const p = amounts.parts;
      const lines: InvoiceLine[] = kind === "service" ?
        [{label: `${b.serviceType ?? "Service"} with ${b.proName ?? "your pro"}`,
          amount: Number(p.rate ?? 0)},
        {label: "Pawgo service fee", amount: Number(p.fee ?? 0)}] :
        [{label: `${p.nights ?? 0} nights at ${b.homeName ?? "the home"}`,
          amount: Number(p.subtotal ?? 0)},
        {label: "Pawgo service fee", amount: Number(p.fee ?? 0)}];

      await sendInvoiceEmail(resendApiKey.value(), MAIL_FROM, {
        to,
        customerName: "",
        heading: kind === "service" ?
          `${b.serviceType ?? "Service"} with ${b.proName ?? "your pro"}` :
          `${b.petName ?? "Your pet"} at ${b.homeName ?? "the home"}`,
        subheading: kind === "service" ?
          `${b.dateLabel ?? ""} ${b.timeSlot ?? ""}`.trim() :
          `${b.checkIn ?? ""} → ${b.checkOut ?? ""}`,
        lines,
        total: amounts.total,
        paymentId,
        bookingId,
      });
    } catch (e) {
      logger.error("verifyBookingPayment: receipt email failed", {bookingId, error: e});
    }

    return {confirmed: true, paymentId};
  });

/**
 * Registers a pro's or host's bank account with Razorpay Route so they can be
 * paid. Raw bank details and PAN pass through and are never persisted here —
 * only the Razorpay account id and a masked last-4.
 */
export const createPayoutAccount = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK,
    secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const uid = request.auth.uid;
    const details = readBankDetails(request.data);

    const existing = await admin.firestore().collection("payoutAccounts").doc(uid).get();
    if (existing.exists && existing.data()?.razorpayAccountId) {
      // Changing bank details means re-onboarding with Razorpay; not supported
      // yet, and silently doing nothing would be worse than saying so.
      throw new HttpsError("failed-precondition", "payout-account-exists");
    }

    const rzp = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });

    let accountId: string;
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ({accountId} = await createLinkedAccount(rzp as any, uid, details));
    } catch (e) {
      // Deliberately does not echo the error back: Razorpay messages can quote
      // the submitted account number.
      logger.error("createPayoutAccount failed", {uid, error: e});
      throw new HttpsError("internal", "payout-account-failed");
    }

    await savePayoutAccount(uid, accountId, details);
    return {status: "pending"};
  });

/**
 * Moves payouts along, once a day.
 *
 * Two jobs, both idempotent so a re-run or a partial failure is harmless:
 *  - `owed` + the partner now has a Route account -> create an ON HOLD transfer.
 *  - `held` + the booking is past its due date -> release it.
 *
 * Held-then-released rather than paid-at-capture because a homestay can still
 * be cancelled for a full refund up to 24h before check-in. Releasing early
 * would mean chasing money a host had already withdrawn.
 */
export const processPayouts = onSchedule(
  {region: REGION, schedule: "every day 02:00", timeZone: "Asia/Kolkata",
    secrets: [razorpayKeyId, razorpayKeySecret]},
  async () => {
    const db = admin.firestore();
    const rzp = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });
    const now = Date.now();

    const setStatus = (
      ref: FirebaseFirestore.DocumentReference,
      status: PayoutStatus,
      extra: Record<string, unknown> = {},
    ) => ref.update({status, updatedAt: Date.now(), ...extra});

    // 1. Create held transfers for anything owed to a partner who can be paid.
    const owed = await db.collection("payouts").where("status", "==", "owed").limit(200).get();
    for (const doc of owed.docs) {
      const p = doc.data();
      const account = await db.collection("payoutAccounts").doc(String(p.partnerId)).get();
      const accountId = account.data()?.razorpayAccountId;
      // No account yet is the normal case, not an error — payout details are
      // optional and earnings simply accrue until they are provided.
      if (!accountId) continue;

      try {
        const transfer = await rzp.payments.transfer(String(p.paymentId), {
          transfers: [{
            account: String(accountId),
            amount: Number(p.amount) * 100, // paise
            currency: "INR",
            on_hold: true,
          }],
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
        } as any);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const id = (transfer as any)?.items?.[0]?.id ?? "";
        await setStatus(doc.ref, "held", {transferId: id, error: ""});
      } catch (e) {
        logger.error("payout transfer failed", {payoutId: doc.id, error: e});
        // Left as `owed`, not `failed`: Route being off is the likeliest cause
        // and it should retry tomorrow rather than need manual resurrection.
        await doc.ref.update({error: "transfer failed", updatedAt: Date.now()});
      }
    }

    // 2. Release held transfers whose booking has completed.
    const held = await db.collection("payouts").where("status", "==", "held").limit(200).get();
    for (const doc of held.docs) {
      const p = doc.data();
      const dueAt = Number(p.dueAt ?? 0);
      if (!dueAt || dueAt > now) continue;
      try {
        await rzp.transfers.edit(String(p.transferId), {on_hold: false});
        await setStatus(doc.ref, "released", {releasedAt: Date.now(), error: ""});
      } catch (e) {
        logger.error("payout release failed", {payoutId: doc.id, error: e});
        await doc.ref.update({error: "release failed", updatedAt: Date.now()});
      }
    }

    logger.info("processPayouts done", {owed: owed.size, held: held.size});
  });

/** Owns `rating`/`reviewCount` on pros and homestays.
 *
 *  These used to be written by the client inside submitReview's transaction,
 *  which forced firestore.rules to allow client writes to them — and because a
 *  rule cannot verify arithmetic, that let any signed-in user set any pro's
 *  rating to 5.0. Rules now reject those fields entirely; the Admin SDK bypasses
 *  rules, so this trigger is the only writer.
 *
 *  Recomputes from the full review set rather than incrementing, so it is
 *  idempotent: Firestore delivers triggers at least once, and a redelivery of
 *  an incrementing handler would double-count. Recomputing also self-heals any
 *  drift left behind by the old client-side aggregation. */
export const onReviewCreated = onDocumentCreated(
  {region: "asia-south1", document: "reviews/{bookingId}"},
  async (event) => {
    const review = event.data?.data();
    if (!review) return;
    const targetId = String(review.targetId ?? "");
    if (!targetId) return;
    const col = review.targetType === "homestay" ? "homestays" : "pros";
    const db = admin.firestore();
    const targetRef = db.collection(col).doc(targetId);

    await db.runTransaction(async (tx) => {
      // Reads before writes, per transaction rules.
      const targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) return; // listing deleted between write and trigger
      const reviews = await tx.get(
        db.collection("reviews").where("targetId", "==", targetId));

      let sum = 0;
      let n = 0;
      reviews.forEach((doc) => {
        const stars = Number(doc.data().stars);
        // Ignore anything out of range rather than letting it skew the mean.
        if (Number.isFinite(stars) && stars >= 1 && stars <= 5) {
          sum += stars;
          n += 1;
        }
      });

      tx.update(targetRef, {rating: n > 0 ? sum / n : 0, reviewCount: n});
    });
    logger.info("onReviewCreated recomputed rating", {col, targetId});

    // targetId is the pro's/host's own uid, so it doubles as the push target.
    await notify({
      scenario: "BOOK8", uid: targetId, key: bookingKey("BOOK8", event.params.bookingId),
      params: {stars: Number(review.stars) || 0, text: String(review.text ?? ""),
        authorName: review.authorName ?? "Someone"},
    });
  });

const DELETED_NAME = "Deleted user";
const DELETED_UID = "deleted";

/** Deletes docs in chunks — Firestore caps a batch at 500 writes. */
async function deleteAll(
  query: FirebaseFirestore.Query, db: FirebaseFirestore.Firestore) {
  const snap = await query.get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    snap.docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  return snap.size;
}

/** Rewrites the author fields on docs the user wrote, leaving the content. */
async function anonymizeAll(
  query: FirebaseFirestore.Query,
  db: FirebaseFirestore.Firestore,
  fields: Record<string, unknown>) {
  const snap = await query.get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    snap.docs.slice(i, i + 400).forEach((d) => batch.update(d.ref, fields));
    await batch.commit();
  }
  return snap.size;
}

/** In-app account deletion — a hard Google Play requirement for any app with
 *  account creation.
 *
 *  Three tiers, chosen because a marketplace cannot simply erase one side of a
 *  transaction:
 *
 *  - DELETED outright: the auth account and everything purely personal —
 *    profile, pets, swipes, and the pro/homestay listings.
 *  - ANONYMIZED: reviews, posts and comments keep their text but lose the
 *    author. Hard-deleting these would gut community threads other people are
 *    reading and silently drop ratings that other users' decisions rest on.
 *  - RETAINED: bookings. They are financial records shared with a counterparty —
 *    the pro or host needs their own history, and refunds reference the
 *    paymentId. The deleted user's name is replaced, so nothing personal
 *    survives beyond the transaction itself.
 *
 *  Storage objects under users/{uid}/ go too. Pet and homestay photos live under
 *  their own prefixes and are removed with their listings.
 *
 *  Runs last: auth deletion is the irreversible step, so a Firestore failure
 *  earlier leaves the account intact and the user can retry. */
export const deleteMyAccount = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const uid = request.auth.uid;
    const db = admin.firestore();

    // Personal content -> gone.
    await deleteAll(db.collection("pets").where("ownerId", "==", uid), db);
    await deleteAll(db.collection("swipes").where("fromUid", "==", uid), db);
    await db.collection("pros").doc(uid).delete();
    await db.collection("homestays").doc(uid).delete();

    // Authored content -> kept, de-identified.
    await anonymizeAll(db.collection("reviews").where("authorId", "==", uid), db,
      {authorId: DELETED_UID, authorName: DELETED_NAME});
    await anonymizeAll(db.collection("posts").where("authorId", "==", uid), db,
      {authorId: DELETED_UID, authorName: DELETED_NAME});
    await anonymizeAll(db.collectionGroup("comments").where("authorId", "==", uid), db,
      {authorId: DELETED_UID, authorName: DELETED_NAME});

    // Bookings are retained untouched as financial records. Nothing is scrubbed
    // because there is nothing to scrub: they store the PROVIDER's name
    // (proName / hostName) and never the customer's, so the only trace of this
    // user is parentId/guestId — an opaque uid with no account behind it once
    // the auth record below is gone. Rewriting those ids would break the pro's
    // and host's own booking history for no privacy gain.

    // Chats: the other participant keeps their thread, but the name shown for
    // this user becomes the tombstone.
    const chats = await db.collection("chats")
      .where("participants", "array-contains", uid).get();
    for (const doc of chats.docs) {
      await doc.ref.update({[`names.${uid}`]: DELETED_NAME});
    }

    // Reviews the user RECEIVED stay put and keep counting — they describe the
    // listing's history, and the listing itself is already gone.

    await db.collection("users").doc(uid).delete();

    try {
      await admin.storage().bucket().deleteFiles({prefix: `users/${uid}/`});
    } catch (e) {
      // Never block deletion of the account on an orphaned file.
      logger.error("deleteMyAccount: storage cleanup failed", {uid, error: e});
    }

    await admin.auth().deleteUser(uid);
    logger.info("deleteMyAccount completed", {uid});
    return {deleted: true};
  });

export const refundBookingPayment = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK,
    secrets: [razorpayKeyId, razorpayKeySecret, resendApiKey]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== "string" || bookingId === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    // Defaults to homestay: this callable was homestay-only until service
    // refunds were added, and an already-installed build sends no `kind`.
    const rawKind = request.data?.kind;
    const kind: Kind = rawKind === "service" ? "service" : "homestay";
    const uid = request.auth.uid;
    const col = kind === "service" ? "bookings" : "homestayBookings";
    const ref = admin.firestore().collection(col).doc(bookingId);

    // Transactionally claim paid -> cancelled: computes the authoritative refund
    // and locks the booking so a double-submit cannot double-refund. Pure (no
    // network); Razorpay is called only after this commits.
    const claim = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "no-booking");
      const b = snap.data() as FirebaseFirestore.DocumentData;

      const ownerField = kind === "service" ? "parentId" : "guestId";
      const paidStatus = kind === "service" ? "confirmed" : "paid";
      if (b[ownerField] !== uid) throw new HttpsError("permission-denied", "not-your-booking");
      if (b.status !== paidStatus) throw new HttpsError("failed-precondition", "not-paid");

      // Both kinds store a date-only YYYY-MM-DD; interpret at IST midnight
      // (Mumbai market). This is a cross-boundary contract shared with the
      // Flutter models — do not "improve" it to full ISO8601.
      const dayField = kind === "service" ? b.date : b.checkIn;
      const startOfDay = new Date(`${String(dayField).slice(0, 10)}T00:00:00+05:30`);
      if (!Number.isFinite(startOfDay.getTime())) {
        throw new HttpsError("failed-precondition", "bad-checkin");
      }
      const now = new Date();
      if (now.getTime() >= startOfDay.getTime()) {
        throw new HttpsError("failed-precondition", "after-checkin");
      }

      // The two policies differ because the products do. A stay is committed
      // capacity, so it uses a 24h window on the subtotal. A service is a
      // single-day appointment and the date has no time-of-day, so an
      // hour-precise rule would be fake precision: cancelling any day before
      // refunds the rate in full. Neither ever refunds the Pawgo fee.
      let refundAmount: number;
      if (kind === "service") {
        refundAmount = (b.rate as number) ?? 0;
      } else {
        const hours = (startOfDay.getTime() - now.getTime()) / 3600000;
        refundAmount = hours >= 24 ? (b.subtotal as number) : 0;
      }

      const paymentId = (b.paymentId as string) || "";
      // A refund needs a payment to refund against — assert BEFORE claiming so
      // this failure is genuinely pre-claim (booking left untouched).
      if (refundAmount > 0 && !paymentId) {
        throw new HttpsError("failed-precondition", "no-payment-id");
      }
      tx.update(ref, {status: "cancelled", updatedAt: Date.now(), refundAmount});
      return {refundAmount, paymentId};
    });

    // Reverse the partner's payout regardless of the refund amount: the booking
    // is cancelled either way, and a held transfer left alone would pay someone
    // for work that never happened.
    try {
      const rzp = new Razorpay({
        key_id: razorpayKeyId.value(),
        key_secret: razorpayKeySecret.value(),
      });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await reversePayout(rzp as any, kind, bookingId);
    } catch (e) {
      logger.error("refundBookingPayment: payout reversal failed", {bookingId, kind, error: e});
    }

    let refundId = "";
    if (claim.refundAmount > 0) {
      let r;
      try {
        const rzp = new Razorpay({
          key_id: razorpayKeyId.value(),
          key_secret: razorpayKeySecret.value(),
        });
        r = await rzp.payments.refund(claim.paymentId,
          {amount: claim.refundAmount * 100, speed: "normal"});
      } catch (e) {
        // Pre-money failure: the booking is already cancelled with refundAmount
        // set but no refund was issued (refundId stays '') — a reconciliation
        // case the client surfaces honestly as "cancelled but refund failed".
        logger.error("refundBookingPayment refund failed", e);
        throw new HttpsError("internal", "refund-failed");
      }
      refundId = r.id;
      // The money HAS moved — persist outside the Razorpay try so a Firestore
      // failure is never reported as a failed refund. Log the id loudly so it
      // stays recoverable.
      try {
        await ref.update({refundId});
      } catch (e) {
        logger.error(
          "refundBookingPayment: refund SUCCEEDED but persisting refundId failed",
          {bookingId, refundId, error: e});
      }
      try {
        const b = (await ref.get()).data() ?? {};
        await sendRefundEmail(resendApiKey.value(), MAIL_FROM, {
          to: await verifiedEmailFor(uid),
          homeName: kind === "service"
            ? `your ${String(b.serviceType ?? "booking")} with ${b.proName ?? "your pro"}`
            : String(b.homeName ?? "the home"),
          amount: claim.refundAmount,
          bookingId,
          refundId,
        });
      } catch (e) {
        logger.error("refundBookingPayment: refund email failed", {bookingId, error: e});
      }
    }
    return {refundAmount: claim.refundAmount, refundId};
  });

export * from "./notify/triggers";
