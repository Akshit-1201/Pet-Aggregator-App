import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {notify} from "./notify";
import type {ScenarioId} from "./catalog";
import {bookingKey, chatKey, matchKey, postKey, verdictKey} from "./keys";
import {maskContactDetails} from "./mask";
import {MAIL_FROM} from "./email";

const REGION = "asia-south1";
const resendApiKey = defineSecret("RESEND_API_KEY");

/** Every email-capable trigger needs the secret bound and the sender passed. */
const mail = () => ({apiKey: resendApiKey.value(), from: MAIL_FROM});

const fmtDay = (iso: string) => {
  const d = new Date(`${String(iso).slice(0, 10)}T00:00:00+05:30`);
  return Number.isFinite(d.getTime()) ?
    d.toLocaleDateString("en-IN", {weekday: "short", day: "numeric", month: "short",
      timeZone: "Asia/Kolkata"}) : String(iso);
};

/** A new chat message notifies the other participant — never someone who has
 *  blocked the sender, which would hand a blocked user a way to keep reaching
 *  into their notification tray.
 *
 *  Also enforces contact masking: the client's maskPhones is a courtesy, and
 *  anyone using the SDK directly bypasses it. */
export const onChatMessageCreated = onDocumentCreated(
  {region: REGION, document: "chats/{chatId}/messages/{messageId}"},
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;
    const senderId = String(msg.senderId ?? "");
    const db = admin.firestore();

    const original = String(msg.text ?? "");
    const masked = maskContactDetails(original);
    let text = original;
    if (masked !== original) {
      text = masked;
      try {
        await event.data!.ref.update({text: masked, masked: true});
        await db.collection("chats").doc(event.params.chatId).update({lastMessage: masked});
      } catch (e) {
        logger.error("contact masking failed to persist",
          {chatId: event.params.chatId, error: e});
      }
    }

    const chat = (await db.collection("chats").doc(event.params.chatId).get()).data();
    if (!chat) return;
    const recipient = (chat.participants as string[] ?? []).find((p) => p !== senderId);
    if (!recipient) return;

    const blocked = await db.collection("users").doc(recipient)
      .collection("blocked").doc(senderId).get();
    if (blocked.exists) return;

    await notify({
      scenario: "MSG1", uid: recipient, key: chatKey(event.params.chatId),
      params: {senderName: (chat.names ?? {})[senderId] ?? "Someone", text},
    });
  });

/** Who a homestayBookings status change notifies: the guest learns the host's
 *  decision (accepted/declined); the host learns what happened to a booking
 *  they're already committed to (paid/cancelled). */
export type HomestayRecipient = "guest" | "host";
export type HomestayDecision = {scenario: ScenarioId; recipient: HomestayRecipient};

/**
 * Maps a homestayBookings status transition to the scenario it fires and who
 * receives it. `null` when there is nothing to send: the status didn't
 * actually change (an update that touched some other field re-delivering, or
 * the trigger firing on its own no-op write), or `after` has no mapping (e.g.
 * "requested", which `onHomestayBookingCreated` handles separately).
 *
 * Pure — no Firestore, no I/O — so the branching itself is unit-testable
 * without the emulator, including the "before === after" no-op case that used
 * to live only as an early-return inside the Firestore trigger. Getting the
 * recipient wrong here (e.g. telling the host their own request was
 * "accepted") would be a silent, high-trust-cost defect that a structure-only
 * catalogue test cannot catch, because the catalogue doesn't know who a
 * scenario is for.
 */
export function homestayStatusScenario(before: string, after: string): HomestayDecision | null {
  if (before === after) return null;
  switch (after) {
  case "accepted": return {scenario: "BOOK4", recipient: "guest"};
  case "declined": return {scenario: "BOOK5", recipient: "guest"};
  case "paid": return {scenario: "BOOK6", recipient: "host"};
  case "cancelled": return {scenario: "BOOK7", recipient: "host"};
  default: return null;
  }
}

/** Homestay lifecycle. The host learns about payment or a cancellation; the
 *  guest learns the host's decision. */
export const onHomestayBookingWritten = onDocumentUpdated(
  {region: REGION, document: "homestayBookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const decision = homestayStatusScenario(String(before.status ?? ""), String(after.status ?? ""));
    if (!decision) return;

    const id = event.params.id;
    const p = {
      petName: after.petName, homeName: after.homeName, nights: after.nights,
      total: after.total, subtotal: after.subtotal,
      checkInLabel: fmtDay(String(after.checkIn ?? "")),
      checkOutLabel: fmtDay(String(after.checkOut ?? "")),
    };
    const uid = decision.recipient === "guest" ?
      String(after.guestId ?? "") : String(after.hostId ?? "");

    await notify({scenario: decision.scenario, uid, key: bookingKey(decision.scenario, id),
      params: p, ...mail()});
  });

export const onHomestayBookingCreated = onDocumentCreated(
  {region: REGION, document: "homestayBookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const b = event.data?.data();
    if (!b || b.status !== "requested") return;
    const id = event.params.id;
    const p = {
      petName: b.petName, homeName: b.homeName, nights: b.nights,
      total: b.total, subtotal: b.subtotal,
      checkInLabel: fmtDay(String(b.checkIn ?? "")),
      checkOutLabel: fmtDay(String(b.checkOut ?? "")),
      bookingId: id,
    };
    // The host must act; the guest gets a written record of what they sent.
    await notify({scenario: "BOOK3", uid: String(b.hostId ?? ""),
      key: bookingKey("BOOK3", id), params: p, ...mail()});
    await notify({scenario: "BOOK9", uid: String(b.guestId ?? ""),
      key: bookingKey("BOOK9", id), params: p, ...mail()});
  });

/** Who a service `bookings` status change notifies. Both mapped statuses tell
 *  the pro today (see the comment below) — "customer" exists in the type so a
 *  future status that should tell the parent instead has somewhere to say so,
 *  rather than silently defaulting to the pro. */
export type ServiceRecipient = "pro" | "customer";
export type ServiceDecision = {scenario: ScenarioId; recipient: ServiceRecipient};

/**
 * Maps a service booking's status transition to the scenario it fires and
 * who receives it. `null` when the status didn't change, or `after` has no
 * mapping. Pure, for the same reason as {@link homestayStatusScenario}:
 * sending BOOK1 ("paid, confirmed") for a booking that was actually
 * cancelled would be a customer-trust incident, not just a copy bug, and
 * nothing else in the test suite would catch it.
 */
export function serviceBookingStatusScenario(
  before: string, after: string,
): ServiceDecision | null {
  if (before === after) return null;
  switch (after) {
  case "confirmed": return {scenario: "BOOK1", recipient: "pro"};
  case "cancelled": return {scenario: "BOOK2", recipient: "pro"};
  default: return null;
  }
}

/** Service bookings: the pro is told when money has landed ('confirmed') and
 *  when a customer cancels and frees the slot. A freshly created but unpaid
 *  booking is deliberately silent for the pro — they have nothing to act on
 *  until it is paid. BOOK10 tells the CUSTOMER, who does. */
export const onServiceBookingWritten = onDocumentUpdated(
  {region: REGION, document: "bookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const decision = serviceBookingStatusScenario(
      String(before.status ?? ""), String(after.status ?? ""));
    if (!decision) return;

    const id = event.params.id;
    const p = {
      petName: after.petName, serviceType: after.serviceType, proName: after.proName,
      dateLabel: after.dateLabel, timeSlot: after.timeSlot, bookingId: id,
    };
    const uid = decision.recipient === "pro" ?
      String(after.proId ?? "") : String(after.parentId ?? "");

    await notify({scenario: decision.scenario, uid, key: bookingKey(decision.scenario, id),
      params: p, ...mail()});
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

    const reciprocal = await admin.firestore().collection("swipes")
      .where("fromUid", "==", ownerId)
      .where("ownerId", "==", fromUid)
      .where("direction", "==", "woof")
      .limit(1).get();
    if (reciprocal.empty) return;

    await Promise.all([
      notify({scenario: "WOOF1", uid: fromUid, key: matchKey(ownerId)}),
      notify({scenario: "WOOF1", uid: ownerId, key: matchKey(fromUid)}),
    ]);
  });

/** A comment on someone's post. Collapses per post — a busy thread must not
 *  become twenty feed rows — but still pushes on every comment. */
export const onCommentCreated = onDocumentCreated(
  {region: REGION, document: "posts/{postId}/comments/{commentId}"},
  async (event) => {
    const c = event.data?.data();
    if (!c) return;
    const authorId = String(c.authorId ?? "");
    const post = (await admin.firestore()
      .collection("posts").doc(event.params.postId).get()).data();
    if (!post) return;
    const postAuthor = String(post.authorId ?? "");
    // Commenting on your own post notifies nobody.
    if (!postAuthor || postAuthor === authorId) return;

    const blocked = await admin.firestore().collection("users").doc(postAuthor)
      .collection("blocked").doc(authorId).get();
    if (blocked.exists) return;

    await notify({
      scenario: "COMM1", uid: postAuthor, key: postKey(event.params.postId),
      params: {authorName: c.authorName ?? "Someone", text: String(c.body ?? ""),
        postTitle: post.title ?? ""},
    });
  });

/** An unpaid service booking. Email-only, to the CUSTOMER: they are looking at
 *  a confirmation screen right now, so a push telling them what they just did
 *  is noise — but the email is the record they'll search for later. */
export const onServiceBookingCreated = onDocumentCreated(
  {region: REGION, document: "bookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const b = event.data?.data();
    if (!b || b.status !== "pending") return;
    const id = event.params.id;
    await notify({
      scenario: "BOOK10", uid: String(b.parentId ?? ""), key: bookingKey("BOOK10", id),
      ...mail(),
      params: {serviceType: b.serviceType, proName: b.proName, dateLabel: b.dateLabel,
        timeSlot: b.timeSlot, total: b.total, bookingId: id},
    });
  });

/** The admin panel's verdict on a KYC submission. Until now the panel flipped
 *  `verified` and the partner was told nothing — so approval was invisible and
 *  rejection looked like the feature was broken. Essential category: a partner
 *  who muted notifications still needs to know their ID check failed. */
export const onVerificationReviewed = onDocumentUpdated(
  {region: REGION, document: "verificationRequests/{uid}", secrets: [resendApiKey]},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    if (after.status !== "approved" && after.status !== "rejected") return;

    const scenario = after.status === "approved" ? "ACC1" : "ACC2";
    const reviewedAt = Number(after.reviewedAt ?? Date.now());
    await notify({
      scenario, uid: event.params.uid, key: verdictKey(scenario, reviewedAt),
      ...mail(),
      params: {reason: String(after.reason ?? "")},
    });
  });
