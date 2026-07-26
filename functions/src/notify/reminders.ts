import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {notify} from "./notify";
import {bookingKey, monthKey} from "./keys";
import {MAIL_FROM} from "./email";

const REGION = "asia-south1";
const resendApiKey = defineSecret("RESEND_API_KEY");

/** 90 days. The feed is a rolling window, not an archive — without this the
 *  collection only ever grows. Email is unaffected: it lives in the
 *  recipient's mailbox, which is the point of sending it. */
const RETENTION_MS = 90 * 24 * 3600 * 1000;

/**
 * The IST calendar day `offsetDays` from `at`, as `YYYY-MM-DD`.
 *
 * Bookings store date-only strings at IST midnight, so every comparison here
 * must happen in IST. Doing it in UTC shifts the boundary by 5.5 hours and
 * fires reminders a day late for anything between 18:30 and midnight IST.
 */
export function istDay(at: number, offsetDays: number): string {
  const ist = new Date(at + 5.5 * 3600 * 1000 + offsetDays * 86400000);
  const y = ist.getUTCFullYear();
  const m = String(ist.getUTCMonth() + 1).padStart(2, "0");
  const d = String(ist.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Runs one reminder pass, isolated: a failure in one must not abort the rest
 *  of the batch or the retention sweep. */
async function step(name: string, fn: () => Promise<void>) {
  try {
    await fn();
  } catch (e) {
    logger.error(`dailyNotifications: ${name} failed`, {error: e});
  }
}

export type OwedPayout = {partnerId?: unknown; amount?: unknown};

/**
 * What each partner is owed, summed across their `owed` payout records.
 *
 * Pure — no Firestore, no I/O — so the arithmetic is unit-testable without a
 * database: a blank/missing partnerId must be skipped rather than bucketed
 * under `""`, and a missing or non-numeric amount must contribute 0 rather
 * than poisoning the running total with NaN (which would render as the
 * literal string "₹NaN" in the reminder email).
 */
export function sumOwedByPartner(payouts: OwedPayout[]): Map<string, number> {
  const totals = new Map<string, number>();
  for (const p of payouts) {
    const partnerId = String(p.partnerId ?? "");
    if (!partnerId) continue;
    const amount = Number(p.amount);
    totals.set(partnerId, (totals.get(partnerId) ?? 0) + (Number.isFinite(amount) ? amount : 0));
  }
  return totals;
}

export const dailyNotifications = onSchedule(
  {region: REGION, schedule: "every day 09:00", timeZone: "Asia/Kolkata",
    secrets: [resendApiKey]},
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const today = istDay(now, 0);
    const tomorrow = istDay(now, 1);
    const yesterday = istDay(now, -1);
    const mail = {apiKey: resendApiKey.value(), from: MAIL_FROM};

    // REM1 — an unpaid service booking whose day has arrived.
    await step("REM1", async () => {
      const snap = await db.collection("bookings")
        .where("status", "==", "pending").where("date", "==", today).limit(300).get();
      for (const d of snap.docs) {
        const b = d.data();
        await notify({scenario: "REM1", uid: String(b.parentId ?? ""),
          key: bookingKey("REM1", d.id),
          params: {serviceType: b.serviceType, proName: b.proName}});
      }
    });

    // REM2 — an accepted stay that still isn't paid, checking in tomorrow.
    await step("REM2", async () => {
      const snap = await db.collection("homestayBookings")
        .where("status", "==", "accepted").where("checkIn", "==", tomorrow).limit(300).get();
      for (const d of snap.docs) {
        const b = d.data();
        await notify({scenario: "REM2", uid: String(b.guestId ?? ""),
          key: bookingKey("REM2", d.id),
          params: {petName: b.petName, homeName: b.homeName}});
      }
    });

    // REM3 — a paid service booking tomorrow. Both sides.
    await step("REM3", async () => {
      const snap = await db.collection("bookings")
        .where("status", "==", "confirmed").where("date", "==", tomorrow).limit(300).get();
      for (const d of snap.docs) {
        const b = d.data();
        const p = {serviceType: b.serviceType, petName: b.petName, timeSlot: b.timeSlot};
        await notify({scenario: "REM3", uid: String(b.parentId ?? ""),
          key: bookingKey("REM3", d.id), params: p});
        await notify({scenario: "REM3", uid: String(b.proId ?? ""),
          key: bookingKey("REM3", d.id), params: p});
      }
    });

    // REM4 — a paid stay checking in tomorrow. Both sides. Mutually exclusive
    // with REM2 by status, so nobody gets both.
    await step("REM4", async () => {
      const snap = await db.collection("homestayBookings")
        .where("status", "==", "paid").where("checkIn", "==", tomorrow).limit(300).get();
      for (const d of snap.docs) {
        const b = d.data();
        const p = {petName: b.petName, homeName: b.homeName, nights: b.nights};
        await notify({scenario: "REM4", uid: String(b.guestId ?? ""),
          key: bookingKey("REM4", d.id), params: p});
        await notify({scenario: "REM4", uid: String(b.hostId ?? ""),
          key: bookingKey("REM4", d.id), params: p});
      }
    });

    // REM5 — yesterday's completed bookings, where no review exists yet.
    await step("REM5", async () => {
      const services = await db.collection("bookings")
        .where("status", "==", "confirmed").where("date", "==", yesterday).limit(300).get();
      const stays = await db.collection("homestayBookings")
        .where("status", "==", "paid").where("checkOut", "==", yesterday).limit(300).get();
      for (const d of [...services.docs, ...stays.docs]) {
        const b = d.data();
        // The review's doc id IS its bookingId — an existing one means done.
        if ((await db.collection("reviews").doc(d.id).get()).exists) continue;
        await notify({scenario: "REM5",
          uid: String(b.parentId ?? b.guestId ?? ""), key: bookingKey("REM5", d.id),
          params: {proName: b.proName, homeName: b.homeName}});
      }
    });

    // PAY5 — earnings stuck because a partner never added bank details. A
    // standing condition rather than an event, so it is swept here and the
    // monthly key keeps it a reminder rather than a nag.
    await step("PAY5", async () => {
      const owed = await db.collection("payouts")
        .where("status", "==", "owed").limit(500).get();
      const totals = sumOwedByPartner(owed.docs.map((d) => d.data()));
      for (const [partnerId, amount] of totals) {
        const account = await db.collection("payoutAccounts").doc(partnerId).get();
        if (account.data()?.razorpayAccountId) continue; // they can be paid
        await notify({scenario: "PAY5", uid: partnerId,
          key: monthKey("PAY5", now), params: {amount}, ...mail});
      }
    });

    // Retention. Drains in bounded pages rather than a single limited read:
    // one page per day would cap daily reclaim below daily production once
    // the app passes PAGE notifications/day, and the feed would grow faster
    // than retention clears it — a slow leak invisible until long after
    // launch. PAGE stays at or below Firestore's 500-write batch cap;
    // MAX_PAGES bounds the run itself so a pathological backlog cannot make
    // the scheduled job run forever.
    await step("retention", async () => {
      const cutoff = now - RETENTION_MS;
      const PAGE = 400;
      const MAX_PAGES = 25; // 10,000 records/run safety bound.
      let deleted = 0;
      let pagesRun = 0;
      for (; pagesRun < MAX_PAGES; pagesRun++) {
        const stale = await db.collectionGroup("items")
          .where("createdAt", "<", cutoff).limit(PAGE).get();
        if (stale.empty) break;
        const batch = db.batch();
        stale.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        deleted += stale.size;
        if (stale.size < PAGE) break; // fewer than a full page: nothing left
      }
      if (pagesRun >= MAX_PAGES) {
        logger.error("notification retention hit the page safety bound; " +
          "more stale records may remain for tomorrow's run", {deleted, MAX_PAGES});
      }
      logger.info("notification retention swept", {deleted, pages: pagesRun});
    });

    logger.info("dailyNotifications done", {today, tomorrow, yesterday});
  });
