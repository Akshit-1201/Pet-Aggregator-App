/**
 * Service time slots: a pro's weekly availability, and the per-day schedule
 * that guarantees two confirmed bookings never overlap.
 *
 * ## Data
 * - `pros/{uid}.availability` — `{weekly: {"1": [{start, end}], ...}, slotMinutes}`
 *   with ISO weekdays ("1" = Monday) and minutes since midnight IST. Absent on
 *   older listings → {@link DEFAULT_AVAILABILITY}, so they stay bookable.
 * - `proSchedule/{proId}_{yyyy-mm-dd}` — `{proId, date, slots: {bookingId: Entry}}`.
 *   ONE document per pro per day on purpose: every hold and confirm runs in a
 *   transaction that reads and writes this doc, which serialises competing
 *   bookings for the same day. (A query over many lock docs would not — a
 *   concurrent insert is invisible to a transaction's query.) Readable by any
 *   signed-in user so the app can grey out taken times; it holds no personal
 *   data, only opaque booking ids and intervals. Server-written only.
 *
 * ## Lifecycle
 * hold (20 min, when the customer heads to payment) → booked (payment
 * verified) → removed (booking cancelled). A hold that lapses stops blocking
 * other customers; an expired hold whose slot someone else then booked is
 * refunded by verifyBookingPayment rather than double-booked.
 */
import {HttpsError} from "firebase-functions/v2/https";

export type Range = {start: number; end: number};
export type Availability = {weekly: Record<string, Range[]>; slotMinutes: number};
export type Entry = {
  startMin: number;
  durationMin: number;
  status: "held" | "booked";
  heldUntil: number;
};

export const HOLD_MS = 20 * 60 * 1000;
export const ALLOWED_SLOT_MINUTES = [30, 45, 60, 90, 120];

const allWeek = (r: Range[]) =>
  Object.fromEntries(["1", "2", "3", "4", "5", "6", "7"].map((d) => [d, r]));

/** Mirrors `Availability.defaults` in the Flutter model — keep them equal. */
export const DEFAULT_AVAILABILITY: Availability = {
  weekly: allWeek([{start: 8 * 60, end: 20 * 60}]),
  slotMinutes: 60,
};

/** Reads `pros/{uid}.availability`, falling back to the default when the
 *  field is missing or malformed — a broken listing must stay bookable. */
export function parseAvailability(raw: unknown): Availability {
  if (!raw || typeof raw !== "object") return DEFAULT_AVAILABILITY;
  const r = raw as Record<string, unknown>;
  const slot = Number(r.slotMinutes);
  const slotMinutes = ALLOWED_SLOT_MINUTES.includes(slot) ? slot : DEFAULT_AVAILABILITY.slotMinutes;
  const weeklyRaw = (r.weekly && typeof r.weekly === "object") ? r.weekly as Record<string, unknown> : null;
  if (!weeklyRaw) return {weekly: DEFAULT_AVAILABILITY.weekly, slotMinutes};
  const weekly: Record<string, Range[]> = {};
  for (const d of ["1", "2", "3", "4", "5", "6", "7"]) {
    const list = Array.isArray(weeklyRaw[d]) ? weeklyRaw[d] as unknown[] : [];
    weekly[d] = list
      .map((x) => x as Record<string, unknown>)
      .map((x) => ({start: Number(x?.start), end: Number(x?.end)}))
      .filter((x) => Number.isInteger(x.start) && Number.isInteger(x.end) &&
        x.start >= 0 && x.end <= 24 * 60 && x.start < x.end);
  }
  return {weekly, slotMinutes};
}

/** ISO weekday (1 = Monday) of a yyyy-mm-dd date. The date is a calendar day
 *  in IST; weekday of a calendar date doesn't depend on timezone. */
export function isoWeekday(date: string): number {
  const d = new Date(`${date}T12:00:00Z`);
  const js = d.getUTCDay(); // 0 = Sunday
  return js === 0 ? 7 : js;
}

/** Epoch ms of `startMin` minutes after IST midnight on `date`. */
export function slotStartEpoch(date: string, startMin: number): number {
  return new Date(`${date}T00:00:00+05:30`).getTime() + startMin * 60000;
}

export const overlaps = (aStart: number, aDur: number, bStart: number, bDur: number) =>
  aStart < bStart + bDur && bStart < aStart + aDur;

/** Entries that still block a time: confirmed bookings, and holds that
 *  haven't lapsed. */
export function isActive(e: Entry, now: number): boolean {
  return e.status === "booked" || Number(e.heldUntil) > now;
}

/** Throws unless [startMin, startMin+durationMin) is a real slot on that day:
 *  the pro's slot length, aligned to and inside an availability window, and
 *  in the future. Server-side so a modified client can't book 3am. */
export function assertBookable(avail: Availability, date: string, startMin: number,
  durationMin: number, now: number): void {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new HttpsError("invalid-argument", "bad-date");
  if (!Number.isInteger(startMin) || startMin < 0 || startMin >= 24 * 60) {
    throw new HttpsError("invalid-argument", "bad-slot");
  }
  if (durationMin !== avail.slotMinutes) throw new HttpsError("failed-precondition", "slot-changed");
  const ranges = avail.weekly[String(isoWeekday(date))] ?? [];
  const fits = ranges.some((r) =>
    startMin >= r.start && startMin + durationMin <= r.end &&
    (startMin - r.start) % avail.slotMinutes === 0);
  if (!fits) throw new HttpsError("failed-precondition", "slot-unavailable");
  if (slotStartEpoch(date, startMin) <= now) throw new HttpsError("failed-precondition", "slot-past");
}

/** The id of an active entry (other than `bookingId`) that clashes, or null. */
export function findConflict(slots: Record<string, Entry>, bookingId: string,
  startMin: number, durationMin: number, now: number): string | null {
  for (const [id, e] of Object.entries(slots)) {
    if (id === bookingId || !isActive(e, now)) continue;
    if (overlaps(startMin, durationMin, Number(e.startMin), Number(e.durationMin))) return id;
  }
  return null;
}

/** Drops lapsed holds so the doc doesn't grow forever. */
export function prune(slots: Record<string, Entry>, now: number): Record<string, Entry> {
  return Object.fromEntries(Object.entries(slots).filter(([, e]) => isActive(e, now)));
}

export const scheduleId = (proId: string, date: string) => `${proId}_${date}`;

/** A booking created by a build that predates time slots has no startMin; such
 *  bookings skip slot enforcement entirely, exactly as before. */
export function slotOf(b: FirebaseFirestore.DocumentData):
    {startMin: number; durationMin: number; date: string} | null {
  if (typeof b.startMin !== "number" || typeof b.durationMin !== "number") return null;
  if (typeof b.date !== "string" || b.date === "") return null;
  return {startMin: b.startMin, durationMin: b.durationMin, date: b.date};
}

/** `slotHolds/{parentId}` — the one live hold a customer may have. Server-only
 *  (no client rule matches it). Deliberately NOT stored on the proSchedule
 *  doc: that doc is readable by every signed-in user, and it would reveal who
 *  booked which pro. */
export type HolderDoc = {bookingId: string; proId: string; date: string};

/**
 * Holds (or re-holds) the booking's slot. Transactional on the pro-day doc.
 * Throws `already-exists/slot-taken` if another active booking overlaps.
 *
 * Abuse limits (security review of the slot feature): without them any
 * signed-in user could create a pending booking per slot and re-hold them all
 * every 19 minutes, blocking a pro's whole calendar for free.
 * - Only a verified account may hold ([verified]: email OR phone); the app's verify gate
 *   is client-side navigation only, so the server has to check.
 * - ONE live hold per customer: holding a new slot releases that customer's
 *   previous hold (if still just a hold), so a re-pick works but a script can
 *   never hold more than one slot per account.
 */
export async function holdSlot(db: FirebaseFirestore.Firestore,
  bookingId: string, b: FirebaseFirestore.DocumentData,
  opts: {verified: boolean}, now = Date.now()): Promise<void> {
  const slot = slotOf(b);
  if (!slot) return;
  if (!opts.verified) throw new HttpsError("permission-denied", "unverified");
  const proId = String(b.proId ?? "");
  const parentId = String(b.parentId ?? "");
  if (!parentId) throw new HttpsError("failed-precondition", "no-parent");
  const pro = await db.collection("pros").doc(proId).get();
  if (!pro.exists) throw new HttpsError("failed-precondition", "no-listing");
  assertBookable(parseAvailability(pro.data()?.availability), slot.date,
    slot.startMin, slot.durationMin, now);

  const ref = db.collection("proSchedule").doc(scheduleId(proId, slot.date));
  const holderRef = db.collection("slotHolds").doc(parentId);
  await db.runTransaction(async (tx) => {
    // Every read happens before any write (Firestore transaction rule).
    const snap = await tx.get(ref);
    const holder = (await tx.get(holderRef)).data() as HolderDoc | undefined;
    const prevRef = holder && holder.bookingId !== bookingId ?
      db.collection("proSchedule").doc(scheduleId(holder.proId, holder.date)) : null;
    const sameDoc = prevRef?.path === ref.path;
    const prevSnap = prevRef && !sameDoc ? await tx.get(prevRef) : null;

    const slots = prune((snap.data()?.slots ?? {}) as Record<string, Entry>, now);
    const mine = slots[bookingId];
    if (mine?.status === "booked") return; // already confirmed — nothing to hold

    // Release this customer's previous HOLD. A confirmed booking is never
    // touched — it stays booked whatever they do next.
    if (holder && prevRef) {
      if (sameDoc) {
        if (slots[holder.bookingId]?.status === "held") delete slots[holder.bookingId];
      } else if (prevSnap?.exists) {
        const prev = prune((prevSnap.data()?.slots ?? {}) as Record<string, Entry>, now);
        if (prev[holder.bookingId]?.status === "held") {
          delete prev[holder.bookingId];
          tx.update(prevRef, {slots: prev, updatedAt: now});
        }
      }
    }

    if (findConflict(slots, bookingId, slot.startMin, slot.durationMin, now)) {
      throw new HttpsError("already-exists", "slot-taken");
    }
    slots[bookingId] = {startMin: slot.startMin, durationMin: slot.durationMin,
      status: "held", heldUntil: now + HOLD_MS};
    tx.set(ref, {proId, date: slot.date, slots, updatedAt: now});
    tx.set(holderRef, {bookingId, proId, date: slot.date, updatedAt: now});
  });
}

/** Removes a booking's entry — on cancellation, so the time frees up at once
 *  instead of when a hold would have lapsed. */
export async function releaseSlot(db: FirebaseFirestore.Firestore,
  bookingId: string, b: FirebaseFirestore.DocumentData, now = Date.now()): Promise<void> {
  const slot = slotOf(b);
  if (!slot) return;
  const ref = db.collection("proSchedule").doc(scheduleId(String(b.proId ?? ""), slot.date));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const slots = prune((snap.data()?.slots ?? {}) as Record<string, Entry>, now);
    delete slots[bookingId];
    // update(), not set({merge: true}): merge deep-merges map fields, so the
    // deleted key would survive and keep blocking the time.
    tx.update(ref, {slots, updatedAt: now});
  });
}

/** A caller has proven ownership of an email (clicked the link) or a phone
 *  number (entered the SMS code — Firebase only sets phone_number then). */
export function isVerifiedCaller(token: {email_verified?: boolean; phone_number?: string}): boolean {
  return token.email_verified === true ||
    (typeof token.phone_number === "string" && token.phone_number !== "");
}
