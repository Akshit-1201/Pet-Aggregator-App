import {Resend} from "resend";
import * as logger from "firebase-functions/logger";

/** Rupee amounts are stored as whole rupees throughout Pawgo (paise only ever
 *  appear at the Razorpay boundary), so no division here. */
const inr = (n: number) => `₹${Number(n || 0).toLocaleString("en-IN")}`;

const esc = (s: unknown) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;");

export type InvoiceLine = {label: string; amount: number};

export type InvoiceInput = {
  to: string;
  customerName: string;
  heading: string;        // "Dog walk with Aarav Sharma"
  subheading: string;     // "Tue 15 Jul · 9:00 AM"
  lines: InvoiceLine[];
  total: number;
  paymentId: string;
  bookingId: string;
};

/** Plain, table-based HTML on purpose: email clients have no flexbox or grid,
 *  strip <style> blocks, and ignore most CSS — inline styles on tables is the
 *  only layout that renders the same in Gmail, Outlook and Apple Mail. */
function invoiceHtml(i: InvoiceInput): string {
  const rows = i.lines.map((l) => `
      <tr>
        <td style="padding:7px 0;color:#6B7280;font-size:14px;">${esc(l.label)}</td>
        <td style="padding:7px 0;text-align:right;color:#111827;font-size:14px;">${inr(l.amount)}</td>
      </tr>`).join("");

  return `<!doctype html>
<html><body style="margin:0;padding:0;background:#FBF1E8;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FBF1E8;padding:28px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:18px;overflow:hidden;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <tr><td style="background:#F0871E;padding:22px 26px;">
          <div style="color:#FFFFFF;font-size:20px;font-weight:800;">Pawgo</div>
          <div style="color:#FFE9D2;font-size:13px;margin-top:2px;">Payment receipt</div>
        </td></tr>
        <tr><td style="padding:24px 26px 8px;">
          <div style="color:#111827;font-size:17px;font-weight:700;">${esc(i.heading)}</div>
          <div style="color:#6B7280;font-size:13px;margin-top:3px;">${esc(i.subheading)}</div>
        </td></tr>
        <tr><td style="padding:8px 26px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${rows}
            <tr><td colspan="2" style="border-top:1px solid #E5E7EB;padding-top:10px;"></td></tr>
            <tr>
              <td style="color:#111827;font-size:15px;font-weight:800;">Total paid</td>
              <td style="text-align:right;color:#F0871E;font-size:17px;font-weight:800;">${inr(i.total)}</td>
            </tr>
          </table>
        </td></tr>
        <tr><td style="padding:20px 26px 26px;">
          <div style="color:#9CA3AF;font-size:12px;line-height:1.6;">
            Payment ID ${esc(i.paymentId)}<br/>
            Booking ${esc(i.bookingId)}<br/>
            Keep this for your records. Questions? Just reply to this email.
          </div>
        </td></tr>
      </table>
      <div style="color:#9CA3AF;font-size:11px;margin-top:14px;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        Pawgo · Mumbai
      </div>
    </td></tr>
  </table>
</body></html>`;
}

function invoiceText(i: InvoiceInput): string {
  const lines = i.lines.map((l) => `  ${l.label}: ${inr(l.amount)}`).join("\n");
  return [
    `Pawgo — payment receipt`, "",
    i.heading, i.subheading, "",
    lines,
    `  Total paid: ${inr(i.total)}`, "",
    `Payment ID: ${i.paymentId}`,
    `Booking: ${i.bookingId}`,
  ].join("\n");
}

/** Sends the receipt. Returns false rather than throwing: the payment has
 *  already succeeded by this point, and a mail outage must never surface to the
 *  user as a failed booking. */
export async function sendInvoiceEmail(
  apiKey: string, from: string, input: InvoiceInput): Promise<boolean> {
  if (!input.to) {
    logger.warn("sendInvoiceEmail: no recipient", {bookingId: input.bookingId});
    return false;
  }
  try {
    const resend = new Resend(apiKey);
    const {error} = await resend.emails.send({
      from,
      to: [input.to],
      subject: `Your Pawgo receipt · ${inr(input.total)}`,
      html: invoiceHtml(input),
      text: invoiceText(input),
    });
    if (error) {
      logger.error("sendInvoiceEmail rejected", {bookingId: input.bookingId, error});
      return false;
    }
    logger.info("invoice emailed", {bookingId: input.bookingId});
    return true;
  } catch (e) {
    logger.error("sendInvoiceEmail threw", {bookingId: input.bookingId, error: e});
    return false;
  }
}

/** Refunds get their own mail — a cancelled booking with money coming back is
 *  exactly when someone wants written confirmation. */
export async function sendRefundEmail(
  apiKey: string, from: string,
  input: {to: string; homeName: string; amount: number; bookingId: string; refundId: string},
): Promise<boolean> {
  if (!input.to) return false;
  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#FBF1E8;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FBF1E8;padding:28px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:18px;overflow:hidden;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <tr><td style="background:#F0871E;padding:22px 26px;">
          <div style="color:#FFFFFF;font-size:20px;font-weight:800;">Pawgo</div>
          <div style="color:#FFE9D2;font-size:13px;margin-top:2px;">Refund confirmed</div>
        </td></tr>
        <tr><td style="padding:24px 26px 26px;">
          <div style="color:#111827;font-size:17px;font-weight:700;">
            ${inr(input.amount)} is on its way back
          </div>
          <div style="color:#6B7280;font-size:14px;margin-top:8px;line-height:1.6;">
            Your stay at ${esc(input.homeName)} was cancelled. Refunds usually reach
            your account in 5–7 working days, depending on your bank.
          </div>
          <div style="color:#9CA3AF;font-size:12px;line-height:1.6;margin-top:18px;">
            Refund ID ${esc(input.refundId)}<br/>Booking ${esc(input.bookingId)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
  try {
    const resend = new Resend(apiKey);
    const {error} = await resend.emails.send({
      from, to: [input.to],
      subject: `Your Pawgo refund · ${inr(input.amount)}`,
      html,
      text: `Pawgo — refund confirmed\n\n${inr(input.amount)} for your cancelled stay ` +
        `at ${input.homeName} is on its way back (5-7 working days).\n\n` +
        `Refund ID: ${input.refundId}\nBooking: ${input.bookingId}`,
    });
    if (error) {
      logger.error("sendRefundEmail rejected", {bookingId: input.bookingId, error});
      return false;
    }
    return true;
  } catch (e) {
    logger.error("sendRefundEmail threw", {bookingId: input.bookingId, error: e});
    return false;
  }
}
