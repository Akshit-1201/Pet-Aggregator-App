import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

/**
 * Marketplace payouts via Razorpay Route.
 *
 * The shape of this is driven by one collision: the app already refunds a
 * homestay in full if the guest cancels 24h+ before check-in. If money has
 * reached the host by then, a refund becomes a clawback from someone who may
 * have already withdrawn it. So transfers are created **on hold** at capture
 * and only released once the booking has actually completed and the
 * cancellation window has closed — Route's `on_hold` flag exists for exactly
 * this. A refund before release simply reverses the held transfer.
 *
 * Nothing here is allowed to break a payment. The payout RECORD is written
 * during payment; every Razorpay call happens later in the scheduled job, so a
 * disabled or misconfigured Route can never make a customer's payment fail.
 */

export type PayoutStatus = "owed" | "held" | "released" | "reversed" | "failed";

export const payoutId = (kind: string, bookingId: string) => `${kind}_${bookingId}`;

/** Platform keeps the fee; the partner gets the rest. Mirrors the amounts the
 *  server already computes when pricing a booking. */
export function partnerAmountOf(kind: string, parts: Record<string, unknown>): number {
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  return kind === "service" ? n(parts.rate) : n(parts.subtotal);
}

/**
 * When the money becomes releasable — the moment the partner has definitely
 * earned it and the customer can no longer cancel for a refund.
 *
 * Services: end of the booking date. Homestays: checkout. Both are stored as
 * date-only `YYYY-MM-DD` at IST midnight, a cross-boundary contract shared with
 * the Flutter models — do not "improve" it to full ISO8601.
 */
export function dueAtFor(kind: string, booking: Record<string, unknown>): number {
  const raw = kind === "service" ? booking.date : booking.checkOut;
  const day = String(raw ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return 0; // legacy row with no machine date
  // End of that day, IST.
  const t = new Date(`${day}T23:59:59+05:30`).getTime();
  return Number.isFinite(t) ? t : 0;
}

/** Records what a partner is owed. Written during payment; no network calls. */
export async function recordPayoutOwed(args: {
  kind: string;
  bookingId: string;
  partnerId: string;
  parts: Record<string, unknown>;
  booking: Record<string, unknown>;
  paymentId: string;
}) {
  const amount = partnerAmountOf(args.kind, args.parts);
  if (!args.partnerId || amount <= 0) return;
  const id = payoutId(args.kind, args.bookingId);
  await admin.firestore().collection("payouts").doc(id).set({
    kind: args.kind,
    bookingId: args.bookingId,
    partnerId: args.partnerId,
    paymentId: args.paymentId,
    amount,
    status: "owed" satisfies PayoutStatus,
    transferId: "",
    dueAt: dueAtFor(args.kind, args.booking),
    createdAt: Date.now(),
    updatedAt: Date.now(),
    error: "",
  });
  logger.info("payout recorded", {id, amount, partnerId: args.partnerId});
}

/** Reverses a held transfer when a booking is refunded. Safe to call when
 *  nothing was ever transferred — the record just becomes `reversed`. */
export async function reversePayout(
  rzp: {transfers: {reverse: (id: string, params: object) => Promise<unknown>}},
  kind: string,
  bookingId: string,
) {
  const ref = admin.firestore().collection("payouts").doc(payoutId(kind, bookingId));
  const snap = await ref.get();
  if (!snap.exists) return;
  const p = snap.data() ?? {};
  if (p.status === "released") {
    // Money already left. Nothing to reverse automatically — flag it loudly so
    // a human reconciles rather than the ledger quietly lying.
    logger.error("refund on an ALREADY RELEASED payout — manual reconciliation needed", {
      bookingId, kind, transferId: p.transferId,
    });
    await ref.update({error: "refunded after release", updatedAt: Date.now()});
    return;
  }
  if (p.status === "held" && p.transferId) {
    try {
      await rzp.transfers.reverse(String(p.transferId), {});
    } catch (e) {
      logger.error("transfer reversal failed", {bookingId, kind, error: e});
      await ref.update({error: "reversal failed", updatedAt: Date.now()});
      return;
    }
  }
  await ref.update({status: "reversed" satisfies PayoutStatus, updatedAt: Date.now()});
}
