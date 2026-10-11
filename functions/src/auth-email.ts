import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {MAIL_FROM, isMailConfigured, sendEmail} from "./notify/email";

const resendApiKey = defineSecret("RESEND_API_KEY");

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
