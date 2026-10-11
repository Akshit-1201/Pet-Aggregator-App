import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {MAIL_FROM, isMailConfigured, sendEmail} from "./notify/email";

const resendApiKey = defineSecret("RESEND_API_KEY");

/** `verificationSends/{uid}` — server-only send log for the cooldown. */
export type SendLog = {lastSentAt: number; windowStart: number; count: number};

export const SEND_COOLDOWN_MS = 60 * 1000;
export const SEND_WINDOW_MS = 24 * 60 * 60 * 1000;
export const SEND_MAX_PER_WINDOW = 5;

/** The log to store if a send is allowed now, or null to refuse it: at most
 *  one email a minute and five a day per account. */
export function nextSendLog(prev: SendLog | undefined, now: number): SendLog | null {
  if (!prev) return {lastSentAt: now, windowStart: now, count: 1};
  if (now - prev.lastSentAt < SEND_COOLDOWN_MS) return null;
  if (now - prev.windowStart >= SEND_WINDOW_MS) return {lastSentAt: now, windowStart: now, count: 1};
  if (prev.count >= SEND_MAX_PER_WINDOW) return null;
  return {lastSentAt: now, windowStart: prev.windowStart, count: prev.count + 1};
}

/** Body of the branded verification email — pure, so it is unit-testable. */
export function verificationEmailBody(name: string, link: string) {
  const first = name.trim().split(/\s+/)[0] || "there";
  return {
    heading: `Confirm your email, ${first}`,
    paragraphs: [
      "Tap the button below to verify your email address and finish setting up " +
        "your Pawgo Pets account.",
      "This keeps Pawgo Pets free of fake accounts, so pet parents and pros can trust each other.",
    ],
    cta: {label: "Verify my email", url: link},
    footer: ["If you didn't create a Pawgo Pets account, you can ignore this email."],
  };
}

/**
 * Sends the email-verification message as a branded HTML email with a real
 * button, instead of Firebase's built-in template.
 *
 * Why: Firebase's verification template cannot have its body edited (the
 * console locks it "to help prevent spam"). It prints the raw URL as the
 * visible text and is sent from noreply@<project>.firebaseapp.com, which
 * often lands in spam — where Gmail disables links. Testers reported "the
 * verification email sends the url as text, not a hyperlink".
 *
 * Returns {sent: false} when Resend is not configured yet (RESEND_API_KEY is
 * still the "unset" placeholder) so the app falls back to Firebase's own
 * email rather than leaving the user with nothing.
 */
export const sendVerificationEmail = onCall(
  {region: "asia-south1", secrets: [resendApiKey]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const key = resendApiKey.value();
    if (!isMailConfigured(key)) return {sent: false, reason: "mail-not-configured"};

    const user = await admin.auth().getUser(request.auth.uid);
    if (!user.email) throw new HttpsError("failed-precondition", "no-email");
    if (user.emailVerified) return {sent: false, reason: "already-verified"};

    // The address is unverified by definition here, so it may belong to
    // someone else entirely (sign up with a victim's address, then call this
    // in a loop). Claim a send slot first; refused calls send nothing.
    const db = admin.firestore();
    const limitRef = db.collection("verificationSends").doc(request.auth.uid);
    const allowed = await db.runTransaction(async (tx) => {
      const prev = (await tx.get(limitRef)).data() as SendLog | undefined;
      const next = nextSendLog(prev, Date.now());
      if (!next) return false;
      tx.set(limitRef, next);
      return true;
    });
    if (!allowed) return {sent: false, reason: "rate-limited"};

    let link: string;
    try {
      link = await admin.auth().generateEmailVerificationLink(user.email);
    } catch (e) {
      // Most often auth/too-many-requests. Let the client fall back.
      logger.warn("generateEmailVerificationLink failed", e);
      return {sent: false, reason: "link-failed"};
    }
    const sent = await sendEmail(key, MAIL_FROM, user.email,
      "Confirm your Pawgo Pets email", verificationEmailBody(user.displayName ?? "", link));
    return {sent, reason: sent ? "ok" : "send-failed"};
  });
