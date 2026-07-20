import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as crypto from "crypto";
import Razorpay from "razorpay";

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
