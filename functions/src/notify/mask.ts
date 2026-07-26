/**
 * Server-side contact-detail masking.
 *
 * The client already masks phone numbers before writing (`maskPhones` in
 * chat.dart), but that is a courtesy, not a control: the Firestore rules let a
 * participant write any text they like, so anyone using the SDK directly
 * bypasses it entirely. This re-masks after the fact, which is the version that
 * actually holds.
 *
 * Deliberately narrow — phone numbers, emails and URLs. Trying to catch
 * addresses would mean guessing at free text and mangling ordinary messages
 * like "I'm on the second floor".
 */
const PHONE_RE = /\+?\d[\d\s().-]{5,}\d/g;
const EMAIL_RE = /[\w.+-]+@[\w-]+\.[\w.-]+/g;
const URL_RE = /\b(?:https?:\/\/|www\.)\S+/gi;

export function maskContactDetails(text: string): string {
  return text
    .replace(EMAIL_RE, "••••")
    .replace(URL_RE, "••••")
    // Phones last: an email's digits shouldn't be re-matched as a number.
    .replace(PHONE_RE, (m) => (m.replace(/\D/g, "").length >= 7 ? "••••" : m));
}
