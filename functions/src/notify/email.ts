import {Resend} from "resend";
import * as logger from "firebase-functions/logger";
import {MAIL_DISABLED, isMailConfigured} from "../invoice";

export {MAIL_DISABLED, isMailConfigured};

/** Whole rupees throughout Pawgo — paise only appear at the Razorpay boundary. */
const inr = (n: number) => `₹${Number(n || 0).toLocaleString("en-IN")}`;

const esc = (s: unknown) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;");

/** Sender for transactional mail. Must be on a domain verified in Resend or
 *  delivery lands in spam. Lives here, not in each caller — three copies of an
 *  address that has to change when the domain is set up is three chances to
 *  miss one. `index.ts` imports this instead of declaring its own. */
export const MAIL_FROM = "Pawgo <receipts@pawgo.app>";

export type EmailRow = {label: string; amount: number};

export type EmailBody = {
  heading: string;
  subheading?: string;
  rows?: EmailRow[];      // line-item table, e.g. a receipt
  paragraphs?: string[];  // prose body, e.g. a refund confirmation
  footer?: string[];      // small grey print, e.g. ids
};

/** Table-based HTML with inline styles on purpose: email clients have no
 *  flexbox or grid, strip <style> blocks, and ignore most CSS. This is the
 *  layout that renders the same in Gmail, Outlook and Apple Mail. */
export function renderEmail(b: EmailBody): {html: string; text: string} {
  const rowsHtml = (b.rows ?? []).map((r) => `
      <tr>
        <td style="padding:7px 0;color:#6B7280;font-size:14px;">${esc(r.label)}</td>
        <td style="padding:7px 0;text-align:right;color:#111827;font-size:14px;">${inr(r.amount)}</td>
      </tr>`).join("");

  const total = (b.rows ?? []).reduce((s, r) => s + Number(r.amount || 0), 0);
  const totalHtml = (b.rows ?? []).length === 0 ? "" : `
            <tr><td colspan="2" style="border-top:1px solid #E5E7EB;padding-top:10px;"></td></tr>
            <tr>
              <td style="color:#111827;font-size:15px;font-weight:800;">Total</td>
              <td style="text-align:right;color:#F0871E;font-size:17px;font-weight:800;">${inr(total)}</td>
            </tr>`;

  const tableHtml = (b.rows ?? []).length === 0 ? "" : `
        <tr><td style="padding:8px 26px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${rowsHtml}${totalHtml}
          </table>
        </td></tr>`;

  const paraHtml = (b.paragraphs ?? []).map((p) => `
          <div style="color:#6B7280;font-size:14px;margin-top:8px;line-height:1.6;">${esc(p)}</div>`)
    .join("");

  const footHtml = (b.footer ?? []).length === 0 ? "" : `
          <div style="color:#9CA3AF;font-size:12px;line-height:1.6;margin-top:18px;">
            ${(b.footer ?? []).map(esc).join("<br/>")}
          </div>`;

  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#FBF1E8;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FBF1E8;padding:28px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:18px;overflow:hidden;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <tr><td style="background:#F0871E;padding:22px 26px;">
          <div style="color:#FFFFFF;font-size:20px;font-weight:800;">Pawgo</div>
        </td></tr>
        <tr><td style="padding:24px 26px 8px;">
          <div style="color:#111827;font-size:17px;font-weight:700;">${esc(b.heading)}</div>
          ${b.subheading ? `<div style="color:#6B7280;font-size:13px;margin-top:3px;">${esc(b.subheading)}</div>` : ""}
          ${paraHtml}
        </td></tr>${tableHtml}
        <tr><td style="padding:20px 26px 26px;">
          ${footHtml}
          <div style="color:#9CA3AF;font-size:12px;line-height:1.6;">
            Questions? Just reply to this email.
          </div>
        </td></tr>
      </table>
      <div style="color:#9CA3AF;font-size:11px;margin-top:14px;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        Pawgo · Mumbai
      </div>
    </td></tr>
  </table>
</body></html>`;

  const text = [
    "Pawgo", "",
    b.heading,
    ...(b.subheading ? [b.subheading] : []),
    ...(b.paragraphs ?? []),
    ...((b.rows ?? []).length ? [""] : []),
    ...(b.rows ?? []).map((r) => `  ${r.label}: ${inr(r.amount)}`),
    ...((b.rows ?? []).length ? [`  Total: ${inr(total)}`] : []),
    ...((b.footer ?? []).length ? [""] : []),
    ...(b.footer ?? []),
  ].join("\n");

  return {html, text};
}

/** Returns false, never throws. By the time email runs the money has already
 *  moved — a mail outage must never surface as a failed payment. */
export async function sendEmail(
  apiKey: string, from: string, to: string, subject: string, body: EmailBody,
): Promise<boolean> {
  if (!isMailConfigured(apiKey)) {
    logger.warn("email not sent: RESEND_API_KEY is not configured", {subject});
    return false;
  }
  if (!to) {
    logger.warn("email not sent: no recipient", {subject});
    return false;
  }
  const {html, text} = renderEmail(body);
  try {
    const {error} = await new Resend(apiKey).emails.send({from, to: [to], subject, html, text});
    if (error) {
      logger.error("email rejected by Resend", {subject, error});
      return false;
    }
    logger.info("email sent", {subject});
    return true;
  } catch (e) {
    logger.error("email threw", {subject, error: e});
    return false;
  }
}
