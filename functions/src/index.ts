import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as crypto from "crypto";
import Razorpay from "razorpay";
import * as admin from "firebase-admin";

admin.initializeApp();

const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");

export const createBookingOrder = onCall(
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const amountRupees = request.data?.amountRupees;
    if (!Number.isInteger(amountRupees) || amountRupees < 1 || amountRupees > 100000) {
      throw new HttpsError("invalid-argument", "bad-amount");
    }
    const rzp = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });
    try {
      const order = await rzp.orders.create({
        amount: amountRupees * 100, // paise
        currency: "INR",
        receipt: `bk_${request.auth.uid}_${Date.now()}`.slice(0, 40),
      });
      return {orderId: order.id, amountPaise: order.amount, keyId: razorpayKeyId.value()};
    } catch (e) {
      logger.error("createBookingOrder failed", e);
      throw new HttpsError("internal", "order-failed");
    }
  });

export const verifyBookingPayment = onCall(
  {region: "asia-south1", secrets: [razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const {orderId, paymentId, signature} = request.data ?? {};
    if (typeof orderId !== "string" || orderId === "" ||
        typeof paymentId !== "string" || paymentId === "" ||
        typeof signature !== "string" || signature === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    const expected = crypto.createHmac("sha256", razorpayKeySecret.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
    const a = Buffer.from(expected);
    const b = Buffer.from(signature);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      throw new HttpsError("permission-denied", "signature-mismatch");
    }
    return {verified: true};
  });

export const refundBookingPayment = onCall(
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
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
      const checkIn = new Date(`${b.checkIn}T00:00:00+05:30`);
      const now = new Date();
      if (now.getTime() >= checkIn.getTime()) {
        throw new HttpsError("failed-precondition", "after-checkin");
      }
      const hours = (checkIn.getTime() - now.getTime()) / 3600000;
      const refundAmount = hours >= 24 ? (b.subtotal as number) : 0;
      tx.update(ref, {status: "cancelled", updatedAt: Date.now(), refundAmount});
      return {refundAmount, paymentId: (b.paymentId as string) || ""};
    });

    let refundId = "";
    if (claim.refundAmount > 0) {
      if (!claim.paymentId) throw new HttpsError("failed-precondition", "no-payment-id");
      try {
        const rzp = new Razorpay({
          key_id: razorpayKeyId.value(),
          key_secret: razorpayKeySecret.value(),
        });
        const r = await rzp.payments.refund(claim.paymentId,
          {amount: claim.refundAmount * 100, speed: "normal"});
        refundId = r.id;
        await ref.update({refundId});
      } catch (e) {
        // The booking is already cancelled with refundAmount set; refundId stays
        // '' (a tracked reconciliation case). Signal distinctly so the client
        // shows an honest "cancelled but refund failed" message.
        logger.error("refundBookingPayment refund failed", e);
        throw new HttpsError("internal", "refund-failed");
      }
    }
    return {refundAmount: claim.refundAmount, refundId};
  });
