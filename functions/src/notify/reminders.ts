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
      const totals = new Map<string, number>();
      for (const d of owed.docs) {
        const p = d.data();
        const partnerId = String(p.partnerId ?? "");
        if (!partnerId) continue;
        totals.set(partnerId, (totals.get(partnerId) ?? 0) + Number(p.amount ?? 0));
      }
      for (const [partnerId, amount] of totals) {
        const account = await db.collection("payoutAccounts").doc(partnerId).get();
        if (account.data()?.razorpayAccountId) continue; // they can be paid
        await notify({scenario: "PAY5", uid: partnerId,
          key: monthKey("PAY5", now), params: {amount}, ...mail});
      }
    });

    // Retention.
    await step("retention", async () => {
      const cutoff = now - RETENTION_MS;
      const stale = await db.collectionGroup("items")
        .where("createdAt", "<", cutoff).limit(400).get();
      for (let i = 0; i < stale.docs.length; i += 400) {
        const batch = db.batch();
        stale.docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
      logger.info("notification retention swept", {deleted: stale.size});
    });

    logger.info("dailyNotifications done", {today, tomorrow, yesterday});
  });
