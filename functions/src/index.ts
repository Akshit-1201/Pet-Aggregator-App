import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as crypto from "crypto";
import Razorpay from "razorpay";
import * as admin from "firebase-admin";
import {sendInvoiceEmail, sendRefundEmail, InvoiceLine} from "./invoice";

admin.initializeApp();

const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");
const resendApiKey = defineSecret("RESEND_API_KEY");

/** Sender for transactional mail. Must be on a domain verified in Resend, or
 *  delivery lands in spam (or is rejected outright). Override per-project with
 *  `firebase functions:config` -> env if the domain changes. */
const MAIL_FROM = "Pawgo <receipts@pawgo.app>";

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

/** Sends one notification to every device a user is signed in on.
 *
 *  Tokens live in users/{uid}/fcmTokens/{token}. They expire when an app is
 *  uninstalled or data-cleared, and FCM rejects those permanently — so dead
 *  tokens are pruned here. Left alone they accumulate forever and every send
 *  slows down behind failures that can never succeed.
 *
 *  `route` travels in the data payload; PushRegistrar deep-links on it.
 *  Failures are logged, never thrown: a push that doesn't send must not roll
 *  back the booking or message that triggered it. */
/** Push categories, matching the toggles in Settings. The field names are the
 *  same ones UserProfile writes. */
type PushCategory = "messages" | "bookings" | "woofs";
const PREF_FIELD: Record<PushCategory, string> = {
  messages: "notifyMessages",
  bookings: "notifyBookings",
  woofs: "notifyWoofs",
};

async function sendPushTo(
  uid: string,
  notification: {title: string; body: string},
  route: string,
  category: PushCategory) {
  if (!uid) return;
  const db = admin.firestore();

  // Preference is checked here, at the source — a toggle that only hid
  // notifications after delivery would not be a preference at all. Absent field
  // means "on": accounts created before these flags existed must not go quiet.
  const profile = (await db.collection("users").doc(uid).get()).data() ?? {};
  if (profile[PREF_FIELD[category]] === false) {
    logger.info("push suppressed by preference", {uid, category});
    return;
  }

  const tokensSnap = await db.collection("users").doc(uid)
    .collection("fcmTokens").get();
  const tokens = tokensSnap.docs.map((d) => d.id);
  if (tokens.length === 0) return;

  let res;
  try {
    res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification,
      data: {route},
      android: {priority: "high", notification: {channelId: "pawgo_default"}},
    });
  } catch (e) {
    logger.error("sendPushTo failed", {uid, error: e});
    return;
  }

  const dead: string[] = [];
  res.responses.forEach((r, i) => {
    const code = r.error?.code ?? "";
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token") {
      dead.push(tokens[i]);
    }
  });
  await Promise.all(dead.map((t) =>
    db.collection("users").doc(uid).collection("fcmTokens").doc(t).delete()
      .catch(() => undefined)));

  logger.info("sendPushTo", {uid, sent: res.successCount, pruned: dead.length});
}

/** A new chat message notifies the other participant — but never someone who
 *  has blocked the sender, which would hand a blocked user a way to keep
 *  reaching into their notification tray. */
export const onChatMessageCreated = onDocumentCreated(
  {region: REGION, document: "chats/{chatId}/messages/{messageId}"},
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;
    const senderId = String(msg.senderId ?? "");
    const db = admin.firestore();
    const chatSnap = await db.collection("chats").doc(event.params.chatId).get();
    const chat = chatSnap.data();
    if (!chat) return;

    const recipient = (chat.participants as string[] ?? [])
      .find((p) => p !== senderId);
    if (!recipient) return;

    const blocked = await db.collection("users").doc(recipient)
      .collection("blocked").doc(senderId).get();
    if (blocked.exists) return;

    const senderName = (chat.names ?? {})[senderId] ?? "Someone";
    await sendPushTo(recipient,
      {title: senderName, body: String(msg.text ?? "").slice(0, 140)},
      "/messages", "messages");
  });

/** Homestay lifecycle. The host learns about a new request (revenue-critical —
 *  this is the one that must never be missed) and about payment or a
 *  cancellation; the guest learns the host's decision. */
export const onHomestayBookingWritten = onDocumentUpdated(
  {region: REGION, document: "homestayBookings/{id}"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const guestId = String(after.guestId ?? "");
    const hostId = String(after.hostId ?? "");
    const homeName = String(after.homeName ?? "the home");
    const petName = String(after.petName ?? "a pet");

    switch (after.status) {
    case "accepted":
      await sendPushTo(guestId,
        {title: "Your stay was accepted", body: `${homeName} can host ${petName}. Pay to confirm.`},
        "/bookings", "bookings");
      break;
    case "declined":
      await sendPushTo(guestId,
        {title: "Your stay request was declined", body: `${homeName} can't host ${petName} then.`},
        "/bookings", "bookings");
      break;
    case "paid":
      await sendPushTo(hostId,
        {title: "A stay is confirmed & paid", body: `${petName} is booked in at ${homeName}.`},
        "/bookings", "bookings");
      break;
    case "cancelled":
      await sendPushTo(hostId,
        {title: "A stay was cancelled", body: `${petName}'s stay at ${homeName} was cancelled.`},
        "/bookings", "bookings");
      break;
    }
  });

export const onHomestayBookingCreated = onDocumentCreated(
  {region: REGION, document: "homestayBookings/{id}"},
  async (event) => {
    const b = event.data?.data();
    if (!b || b.status !== "requested") return;
    await sendPushTo(String(b.hostId ?? ""),
      {title: "New booking request",
        body: `${b.petName ?? "A pet"} needs a place — ${b.nights ?? "?"} nights.`},
      "/bookings", "bookings");
  });

/** Service bookings: the pro is told when money has actually landed
 *  ('confirmed'), and when a customer cancels and frees the slot. A freshly
 *  created but unpaid booking is deliberately silent — the customer just made
 *  it, and the pro has nothing to act on until it is paid. */
export const onServiceBookingWritten = onDocumentUpdated(
  {region: REGION, document: "bookings/{id}"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const petName = String(after.petName ?? "A pet");
    const dateLabel = String(after.dateLabel ?? "");
    if (after.status === "confirmed") {
      await sendPushTo(String(after.proId ?? ""),
        {title: "New booking, paid", body: `${petName} · ${dateLabel}`},
        "/bookings", "bookings");
    } else if (after.status === "cancelled") {
      await sendPushTo(String(after.proId ?? ""),
        {title: "A booking was cancelled", body: `${petName} · ${dateLabel}`},
        "/bookings", "bookings");
    }
  });

/** A reciprocal Woof is the payoff moment of Discover, and neither side sees it
 *  unless they happen to be in the deck — so both get told. */
export const onSwipeCreated = onDocumentCreated(
  {region: REGION, document: "swipes/{id}"},
  async (event) => {
    const swipe = event.data?.data();
    if (!swipe || swipe.direction !== "woof") return;
    const fromUid = String(swipe.fromUid ?? "");
    const ownerId = String(swipe.ownerId ?? "");
    if (!fromUid || !ownerId || fromUid === ownerId) return;

    // Did the other owner already woof one of this user's pets?
    const reciprocal = await admin.firestore().collection("swipes")
      .where("fromUid", "==", ownerId)
      .where("ownerId", "==", fromUid)
      .where("direction", "==", "woof")
      .limit(1)
      .get();
    if (reciprocal.empty) return;

    const body = "You both woofed. Say hello!";
    await Promise.all([
      sendPushTo(fromUid, {title: "It's a match! 🐾", body}, "/discover", "woofs"),
      sendPushTo(ownerId, {title: "It's a match! 🐾", body}, "/discover", "woofs"),
    ]);
  });

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
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
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
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret, resendApiKey]},
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
    const stars = "★".repeat(Math.max(0, Math.min(5, Number(review.stars) || 0)));
    await sendPushTo(targetId,
      {title: `New ${stars} review`,
        body: String(review.text ?? "").trim() ||
          `${review.authorName ?? "Someone"} rated you.`},
      "/bookings", "bookings");
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
  {region: "asia-south1"},
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
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret, resendApiKey]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== "string" || bookingId === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    const uid = request.auth.uid;
    const ref = admin.firestore().collection("homestayBookings").doc(bookingId);

    // Transactionally claim paid -> cancelled: computes the authoritative refund
    // and locks the booking so a double-submit cannot double-refund. Pure (no
    // network); Razorpay is called only after this commits.
    const claim = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "no-booking");
      const b = snap.data() as FirebaseFirestore.DocumentData;
      if (b.guestId !== uid) throw new HttpsError("permission-denied", "not-your-booking");
      if (b.status !== "paid") throw new HttpsError("failed-precondition", "not-paid");
      // checkIn is a date (YYYY-MM-DD); interpret at IST midnight (Mumbai market).
      const checkIn = new Date(`${String(b.checkIn).slice(0, 10)}T00:00:00+05:30`);
      if (!Number.isFinite(checkIn.getTime())) {
        throw new HttpsError("failed-precondition", "bad-checkin");
      }
      const now = new Date();
      if (now.getTime() >= checkIn.getTime()) {
        throw new HttpsError("failed-precondition", "after-checkin");
      }
      const hours = (checkIn.getTime() - now.getTime()) / 3600000;
      const refundAmount = hours >= 24 ? (b.subtotal as number) : 0;
      const paymentId = (b.paymentId as string) || "";
      // A refund needs a payment to refund against — assert BEFORE claiming so
      // this failure is genuinely pre-claim (booking left untouched).
      if (refundAmount > 0 && !paymentId) {
        throw new HttpsError("failed-precondition", "no-payment-id");
      }
      tx.update(ref, {status: "cancelled", updatedAt: Date.now(), refundAmount});
      return {refundAmount, paymentId};
    });

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
          homeName: String(b.homeName ?? "the home"),
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
