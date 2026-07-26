# Pawgo Slice 21: Notification scenarios + engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one server-side catalogue the single source of every notification Pawgo sends — 25 scenarios across push and email — so the in-app feed, push and email can never disagree, and adding a scenario is one catalogue entry rather than three implementations.

**Architecture:** A typed catalogue (`functions/src/notify/catalog.ts`) declares each scenario's category, channels, dedupe behaviour and renderers. One entry point, `notify()`, writes a record to `notifications/{uid}/items/{key}`, then sends push (preference-gated) and email (never gated) independently. The doc id **is** the dedupe key, which makes at-least-once trigger redelivery harmless on both channels. A new `dailyNotifications` scheduled Function adds the five time-based reminders, the payout-blocked sweep and 90-day retention. The client's `buildNotifications` derivation is deleted and replaced by a stream read.

**Tech Stack:** Firebase Functions v2 (TypeScript, `firebase-admin`, `resend` — all present) + `vitest` (new); Flutter/Dart ^3.12.2, `flutter_riverpod` 3.x, `go_router`, `cloud_firestore`, `firebase_messaging`.

**Spec:** `docs/superpowers/specs/2026-07-26-pawgo-notification-engine-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **No new Flutter packages and no new secrets.** `vitest` is the only new dependency, and it is a `functions/` devDependency.
- **`RESEND_API_KEY` stays the literal `"unset"`.** Never change it, never remove the `isMailConfigured()` short-circuit. Email must deploy inert.
- **Region is `asia-south1`** for every Function. The existing `REGION` constant in `functions/src/index.ts`.
- **Scenario ids are the literal strings** `MSG1`, `BOOK1`–`BOOK10`, `WOOF1`, `COMM1`, `PAY1`–`PAY5`, `ACC1`, `ACC2`, `REM1`–`REM5`. They appear in Firestore documents; do not rename them mid-plan.
- **Categories:** `messages` · `bookings` · `woofs` · `community` · `reminders` · `money` · `account`. The last two are `essential: true` — push ignores preferences.
- **Preference fields on `users/{uid}`:** `notifyMessages`, `notifyBookings`, `notifyWoofs`, `notifyCommunity`, `notifyReminders`. **Absent means ON.** Only `=== false` suppresses.
- **Preferences gate push only. Email is never gated by a preference.**
- **`notify()` never throws.** Every channel is wrapped. A notification failure must not roll back the booking, message or payment that triggered it.
- **Dates are date-only `YYYY-MM-DD` at IST midnight** (`Booking.date`, `HomestayBooking.checkIn`/`checkOut`) — a cross-boundary contract shared with the Flutter models. Do not "improve" it to full ISO8601. All reminder date math resolves in **IST (`+05:30`)**, never UTC.
- **Rupee amounts are whole rupees** everywhere except the Razorpay boundary (paise).
- `createdAt`/`updatedAt` are millisecond ints (`Date.now()`).
- Riverpod 3.x uses `.value` (not `valueOrNull`); async handlers guard `context.mounted`; widget tests use `pumpPgApp` from `test/support/pump.dart` with fakes from `test/support/fakes.dart`.
- **Every task ends green:** `npm --prefix functions run build` + `npm --prefix functions test` for TS tasks; `flutter analyze` clean + `flutter test` green for Dart tasks. Then commit. **Do NOT push. Do NOT deploy.**

---

### Task 1: `vitest` + the shared email shell

Generalises `functions/src/invoice.ts` into a reusable shell. The existing table-based HTML is the only layout that renders consistently in Gmail, Outlook and Apple Mail — it is being **generalised, not rewritten**.

**Files:**
- Modify: `functions/package.json`
- Modify: `functions/tsconfig.json`
- Create: `functions/src/notify/email.ts`
- Create: `functions/src/notify/email.test.ts`

**Interfaces:**
- Produces: `renderEmail(input: EmailBody): {html: string; text: string}`; `sendEmail(apiKey: string, from: string, to: string, subject: string, body: EmailBody): Promise<boolean>`; `type EmailBody = {heading: string; subheading?: string; rows?: EmailRow[]; paragraphs?: string[]; footer?: string[]}`; `type EmailRow = {label: string; amount: number}`; re-exports `MAIL_DISABLED` and `isMailConfigured` from `../invoice`.

- [ ] **Step 1: Add vitest and exclude tests from the build**

In `functions/package.json`, replace the `scripts` and `devDependencies` blocks:

```json
  "scripts": {
    "build": "tsc",
    "test": "vitest run"
  },
```

```json
  "devDependencies": {
    "typescript": "^5.7.0",
    "vitest": "^3.2.0"
  }
```

In `functions/tsconfig.json`, add an `exclude` alongside `include` so test files never compile into `lib/`:

```json
  "include": ["src"],
  "exclude": ["src/**/*.test.ts"]
```

Run: `npm --prefix functions install`

- [ ] **Step 2: Write the failing test**

Create `functions/src/notify/email.test.ts`:

```ts
import {describe, it, expect, vi, beforeEach} from "vitest";
import {renderEmail, sendEmail} from "./email";

describe("renderEmail", () => {
  it("renders a line-item table from rows", () => {
    const {html, text} = renderEmail({
      heading: "Dog walk with Rahul",
      subheading: "Tue 15 Jul · 9:00 AM",
      rows: [{label: "Dog walk", amount: 400}, {label: "Pawgo service fee", amount: 40}],
    });
    expect(html).toContain("Dog walk with Rahul");
    expect(html).toContain("₹400");
    expect(html).toContain("₹40");
    expect(text).toContain("Dog walk: ₹400");
  });

  it("renders paragraphs when there are no rows", () => {
    const {html, text} = renderEmail({
      heading: "₹3,200 is on its way back",
      paragraphs: ["Refunds usually reach your account in 5–7 working days."],
    });
    expect(html).toContain("5–7 working days");
    expect(text).toContain("5–7 working days");
    expect(html).not.toContain("<tr><td colspan=\"2\"");
  });

  it("escapes HTML so a pet name cannot inject markup", () => {
    const {html} = renderEmail({heading: "<script>alert(1)</script> checks in"});
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("formats rupees in the Indian numbering system", () => {
    const {html} = renderEmail({heading: "x", rows: [{label: "Stay", amount: 125000}]});
    expect(html).toContain("₹1,25,000");
  });

  it("renders footer lines when given", () => {
    const {text} = renderEmail({heading: "x", footer: ["Payment ID pay_123"]});
    expect(text).toContain("Payment ID pay_123");
  });

  // A receipt is the one body that uses rows AND footer together, and it is the
  // most-sent email in the catalogue. Pin the order in both renderings.
  it("puts the footer below the line items in HTML, matching the text order", () => {
    const body = {
      heading: "Dog walk with Rahul",
      rows: [{label: "Dog walk", amount: 400}],
      footer: ["Payment ID pay_123"],
    };
    const {html, text} = renderEmail(body);
    expect(html.indexOf("Payment ID pay_123")).toBeGreaterThan(html.indexOf("Dog walk</td>"));
    expect(text.indexOf("Payment ID pay_123")).toBeGreaterThan(text.indexOf("Dog walk: ₹400"));
  });
});

// Spy on the SDK itself. Asserting only the return value would not catch a
// regressed `isMailConfigured` guard: execution would fall through to a real
// `new Resend("unset").emails.send(...)`, still return false via the catch
// path, and leave this suite green while firing live API calls.
const sendSpy = vi.fn(async () => ({data: {id: "e_1"}, error: null}));
vi.mock("resend", () => ({
  Resend: vi.fn().mockImplementation(() => ({emails: {send: sendSpy}})),
}));

describe("sendEmail", () => {
  beforeEach(() => sendSpy.mockClear());

  it("returns false WITHOUT calling Resend when the key is the placeholder", async () => {
    const ok = await sendEmail("unset", "Pawgo <a@b.com>", "x@y.com", "Subject",
      {heading: "x"});
    expect(ok).toBe(false);
    expect(sendSpy).not.toHaveBeenCalled();
  });

  it("returns false WITHOUT calling Resend when there is no recipient", async () => {
    const ok = await sendEmail("re_realkey", "Pawgo <a@b.com>", "", "Subject",
      {heading: "x"});
    expect(ok).toBe(false);
    expect(sendSpy).not.toHaveBeenCalled();
  });

  // Positive control: without this, a spy that never fires would make both
  // assertions above vacuously true.
  it("does call Resend with a configured key and a real recipient", async () => {
    const ok = await sendEmail("re_realkey", "Pawgo <a@b.com>", "x@y.com", "Subject",
      {heading: "x"});
    expect(ok).toBe(true);
    expect(sendSpy).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL — `Cannot find module './email'`

- [ ] **Step 4: Write the email shell**

Create `functions/src/notify/email.ts`:

```ts
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

  // Rendered AFTER the line-item table, matching the text alternative's order.
  // A receipt's small print (payment id, booking id) belongs below the total —
  // putting it in the heading block instead would place it above the items in
  // HTML while the plain-text version put it below, and PAY1 uses both.
  const footHtml = (b.footer ?? []).length === 0 ? "" : `
        <tr><td style="padding:14px 26px 0;">
          <div style="color:#9CA3AF;font-size:12px;line-height:1.6;">
            ${(b.footer ?? []).map(esc).join("<br/>")}
          </div>
        </td></tr>`;

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
        </td></tr>${tableHtml}${footHtml}
        <tr><td style="padding:20px 26px 26px;">
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
```

- [ ] **Step 5: Run the tests and the build**

Run: `npm --prefix functions test`
Expected: PASS — 9 tests

Run: `npm --prefix functions run build`
Expected: exit 0, no output

- [ ] **Step 6: Commit**

```bash
git add functions/package.json functions/package-lock.json functions/tsconfig.json functions/src/notify/email.ts functions/src/notify/email.test.ts
git commit -m "feat: shared email shell + vitest in functions"
```

---

### Task 2: The scenario catalogue

Pure data and pure render functions. No Firebase, no I/O — which is exactly why it is worth testing on its own.

**Files:**
- Create: `functions/src/notify/catalog.ts`
- Create: `functions/src/notify/catalog.test.ts`

**Interfaces:**
- Consumes: `EmailBody`, `EmailRow` from Task 1's `./email`.
- Produces: `type PushCategory = "messages" | "bookings" | "woofs" | "community" | "reminders" | "money" | "account"`; `const PREF_FIELD: Record<PushCategory, string>`; `type Scenario`; `const CATALOG: Record<ScenarioId, Scenario>`; `type ScenarioId`; `const ESSENTIAL: ReadonlySet<PushCategory>`.

- [ ] **Step 1: Write the failing test**

Create `functions/src/notify/catalog.test.ts`:

```ts
import {describe, it, expect} from "vitest";
import {CATALOG, PREF_FIELD, type ScenarioId} from "./catalog";

const ids = Object.keys(CATALOG) as ScenarioId[];

const PARAMS: Record<string, Record<string, unknown>> = {
  senderName: "Rahul", text: "Hello there", petName: "Bruno", homeName: "Sunny Villa",
  proName: "Rahul", serviceType: "Dog walking", dateLabel: "Tue 15 Jul", timeSlot: "9:00 AM",
  checkInLabel: "Tue 15 Jul", checkOutLabel: "Thu 17 Jul", nights: 2, total: 3200,
  amount: 720, rate: 400, fee: 40, subtotal: 3050, stars: 5, authorName: "Priya",
  postTitle: "Best vet in Bandra", paymentId: "pay_123", refundId: "rfnd_1",
  bookingId: "bk_1", reason: "The ID photo was blurred", area: "Bandra",
};

describe("catalog", () => {
  it("has exactly the 25 specified scenarios", () => {
    expect(ids.sort()).toEqual([
      "ACC1", "ACC2",
      "BOOK1", "BOOK10", "BOOK2", "BOOK3", "BOOK4", "BOOK5", "BOOK6", "BOOK7", "BOOK8", "BOOK9",
      "COMM1", "MSG1",
      "PAY1", "PAY2", "PAY3", "PAY4", "PAY5",
      "REM1", "REM2", "REM3", "REM4", "REM5",
      "WOOF1",
    ]);
  });

  it("every scenario renders a non-empty title and body", () => {
    for (const id of ids) {
      const {title, body} = CATALOG[id].render(PARAMS);
      expect(title, `${id} title`).toBeTruthy();
      expect(body, `${id} body`).toBeTruthy();
    }
  });

  it("every scenario declares at least one channel", () => {
    for (const id of ids) expect(CATALOG[id].channels.length, id).toBeGreaterThan(0);
  });

  it("every email scenario has an email renderer producing a subject and heading", () => {
    for (const id of ids) {
      const s = CATALOG[id];
      if (!s.channels.includes("email")) continue;
      expect(s.email, `${id} needs an email renderer`).toBeDefined();
      const e = s.email!(PARAMS);
      expect(e.subject, `${id} subject`).toBeTruthy();
      expect(e.body.heading, `${id} heading`).toBeTruthy();
    }
  });

  it("no email scenario also collapses — a collapsing record would re-email", () => {
    for (const id of ids) {
      const s = CATALOG[id];
      if (s.collapse) expect(s.channels.includes("email"), id).toBe(false);
    }
  });

  it("money and account are the only essential categories", () => {
    for (const id of ids) {
      const s = CATALOG[id];
      const expected = s.category === "money" || s.category === "account";
      expect(s.essential, id).toBe(expected);
    }
  });

  it("maps every category to a preference field", () => {
    for (const id of ids) expect(PREF_FIELD[CATALOG[id].category], id).toBeTruthy();
  });

  it("the service refund email never calls a service booking a stay", () => {
    const e = CATALOG.PAY2.email!({...PARAMS, kind: "service"});
    const blob = `${e.subject} ${e.body.heading} ${(e.body.paragraphs ?? []).join(" ")}`;
    expect(blob.toLowerCase()).not.toContain("stay at");
    expect(blob).toContain("Dog walking");
  });

  it("the homestay refund email does describe a stay", () => {
    const e = CATALOG.PAY2.email!({...PARAMS, kind: "homestay"});
    const blob = `${e.body.heading} ${(e.body.paragraphs ?? []).join(" ")}`;
    expect(blob).toContain("Sunny Villa");
  });

  it("PAY3 explains that no refund is due", () => {
    const {title, body} = CATALOG.PAY3.render(PARAMS);
    expect(`${title} ${body}`.toLowerCase()).toContain("no refund");
  });

  it("ACC2 includes the rejection reason", () => {
    const {body} = CATALOG.ACC2.render(PARAMS);
    expect(body).toContain("The ID photo was blurred");
  });

  it("BOOK9 and BOOK10 are email-only", () => {
    expect(CATALOG.BOOK9.channels).toEqual(["email"]);
    expect(CATALOG.BOOK10.channels).toEqual(["email"]);
  });

  it("every route starts with a slash", () => {
    for (const id of ids) expect(CATALOG[id].route.startsWith("/"), id).toBe(true);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL — `Cannot find module './catalog'`

- [ ] **Step 3: Write the catalogue**

Create `functions/src/notify/catalog.ts`:

```ts
import type {EmailBody, EmailRow} from "./email";

export type PushCategory =
  | "messages" | "bookings" | "woofs" | "community" | "reminders" | "money" | "account";

/** Field names on users/{uid}. Absent means ON — accounts predating a flag
 *  must not silently go quiet. */
export const PREF_FIELD: Record<PushCategory, string> = {
  messages: "notifyMessages",
  bookings: "notifyBookings",
  woofs: "notifyWoofs",
  community: "notifyCommunity",
  reminders: "notifyReminders",
  money: "notifyMoney",     // never read: money is essential
  account: "notifyAccount", // never read: account is essential
};

/** Categories whose push ignores preferences. Failing to tell someone their
 *  refund landed or their ID was rejected is a support incident, not a
 *  preference. */
export const ESSENTIAL: ReadonlySet<PushCategory> = new Set<PushCategory>(["money", "account"]);

export type Channel = "push" | "email";
export type P = Record<string, unknown>;

/** Declared explicitly rather than inferred from CATALOG. `as const satisfies`
 *  would narrow `channels` to a readonly tuple of literals, and then
 *  `channels.includes("email")` fails to typecheck on a `["push"]` entry — and
 *  `spec.email` would not exist on the union at all. */
export type ScenarioId =
  | "MSG1"
  | "BOOK1" | "BOOK2" | "BOOK3" | "BOOK4" | "BOOK5"
  | "BOOK6" | "BOOK7" | "BOOK8" | "BOOK9" | "BOOK10"
  | "WOOF1" | "COMM1"
  | "PAY1" | "PAY2" | "PAY3" | "PAY4" | "PAY5"
  | "ACC1" | "ACC2"
  | "REM1" | "REM2" | "REM3" | "REM4" | "REM5";

export type Scenario = {
  category: PushCategory;
  essential: boolean;
  /** Overwrite the existing record instead of adding one. Push still fires per
   *  event; the feed keeps a single row. Never combined with email. */
  collapse: boolean;
  route: string;
  channels: Channel[];
  render: (p: P) => {title: string; body: string};
  email?: (p: P) => {subject: string; body: EmailBody};
};

const s = (p: P, k: string, fallback = "") => {
  const v = p[k];
  return v === undefined || v === null || v === "" ? fallback : String(v);
};
const n = (p: P, k: string) => Number(p[k] ?? 0);
const inr = (v: number) => `₹${Number(v || 0).toLocaleString("en-IN")}`;

/** What was booked, in words, for whichever pillar this is. Keeps every
 *  money template pillar-correct — the bug that made refund emails say
 *  "Your stay at your Dog walking with Rahul was cancelled". */
const subject = (p: P) => s(p, "kind") === "service" ?
  `${s(p, "serviceType", "your booking")} with ${s(p, "proName", "your pro")}` :
  `your stay at ${s(p, "homeName", "the home")}`;

const receiptLines = (p: P): EmailRow[] => s(p, "kind") === "service" ?
  [{label: `${s(p, "serviceType", "Service")} with ${s(p, "proName", "your pro")}`, amount: n(p, "rate")},
    {label: "Pawgo service fee", amount: n(p, "fee")}] :
  [{label: `${n(p, "nights")} nights at ${s(p, "homeName", "the home")}`, amount: n(p, "subtotal")},
    {label: "Pawgo service fee", amount: n(p, "fee")}];

const BOOKINGS = "/bookings";

export const CATALOG: Record<ScenarioId, Scenario> = {
  // ---------- messages ----------
  MSG1: {
    category: "messages", essential: false, collapse: true,
    route: "/messages", channels: ["push"],
    render: (p) => ({title: s(p, "senderName", "Someone"), body: s(p, "text").slice(0, 140)}),
  },

  // ---------- bookings ----------
  BOOK1: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "New booking, paid",
      body: `${s(p, "petName", "A pet")} · ${s(p, "dateLabel")}`.trim()}),
    email: (p) => ({
      subject: `New Pawgo booking · ${s(p, "dateLabel")}`,
      body: {heading: `${s(p, "serviceType", "A booking")} for ${s(p, "petName", "a pet")}`,
        subheading: `${s(p, "dateLabel")} ${s(p, "timeSlot")}`.trim(),
        paragraphs: ["This booking is paid and confirmed. You'll be paid out after it's done."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  BOOK2: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "A booking was cancelled",
      body: `${s(p, "petName", "A pet")} · ${s(p, "dateLabel")}`.trim()}),
    email: (p) => ({
      subject: `Cancelled · ${s(p, "dateLabel")}`,
      body: {heading: `${s(p, "serviceType", "A booking")} was cancelled`,
        subheading: `${s(p, "petName", "A pet")} · ${s(p, "dateLabel")}`,
        paragraphs: ["That slot is free again in your calendar."]},
    }),
  },
  BOOK3: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "New booking request",
      body: `${s(p, "petName", "A pet")} needs a place — ${n(p, "nights")} nights.`}),
    email: (p) => ({
      subject: `New stay request · ${s(p, "petName", "a pet")}`,
      body: {heading: `${s(p, "petName", "A pet")} needs a place`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: ["Open Pawgo to accept or decline. Requests expire on the check-in date."],
        footer: [`You'd earn ${inr(n(p, "subtotal"))}`]},
    }),
  },
  BOOK4: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "Your stay was accepted",
      body: `${s(p, "homeName", "The host")} can host ${s(p, "petName", "your pet")}. Pay to confirm.`}),
    email: (p) => ({
      subject: `Accepted — pay to confirm ${s(p, "petName", "your pet")}'s stay`,
      body: {heading: `${s(p, "homeName", "The host")} accepted your request`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: [`Pay ${inr(n(p, "total"))} in the Pawgo app to confirm. ` +
          "The booking isn't held until it's paid."]},
    }),
  },
  BOOK5: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "Your stay request was declined",
      body: `${s(p, "homeName", "The host")} can't host ${s(p, "petName", "your pet")} then.`}),
    email: (p) => ({
      subject: "Your Pawgo stay request was declined",
      body: {heading: `${s(p, "homeName", "The host")} can't host those dates`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")}`,
        paragraphs: ["Nothing was charged. There are other homes in your area on Pawgo."]},
    }),
  },
  BOOK6: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "A stay is confirmed & paid",
      body: `${s(p, "petName", "A pet")} is booked in at ${s(p, "homeName", "your home")}.`}),
    email: (p) => ({
      subject: `Confirmed · ${s(p, "petName", "a pet")} from ${s(p, "checkInLabel")}`,
      body: {heading: `${s(p, "petName", "A pet")} is booked in`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: [`You'll receive ${inr(n(p, "subtotal"))} after checkout.`]},
    }),
  },
  BOOK7: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "A stay was cancelled",
      body: `${s(p, "petName", "A pet")}'s stay at ${s(p, "homeName", "your home")} was cancelled.`}),
    email: (p) => ({
      subject: `Cancelled · ${s(p, "checkInLabel")}`,
      body: {heading: `${s(p, "petName", "A pet")}'s stay was cancelled`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")}`,
        paragraphs: ["Those dates are free again in your calendar."]},
    }),
  },
  BOOK8: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({
      title: `New ${"★".repeat(Math.max(0, Math.min(5, Math.trunc(n(p, "stars")))))} review`,
      body: s(p, "text").trim() || `${s(p, "authorName", "Someone")} rated you.`}),
  },
  BOOK9: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["email"],
    render: (p) => ({title: "Stay request sent",
      body: `${s(p, "homeName", "The host")} · ${n(p, "nights")} nights`}),
    email: (p) => ({
      subject: `We've got your request for ${s(p, "homeName", "a stay")}`,
      body: {heading: "Your stay request is with the host",
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: [`${s(p, "homeName", "The host")} will accept or decline. ` +
          `Nothing is charged until you pay to confirm — ${inr(n(p, "total"))} if accepted.`],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  BOOK10: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["email"],
    render: (p) => ({title: "Booking created — pay to confirm",
      body: `${s(p, "serviceType", "Service")} · ${s(p, "dateLabel")}`}),
    email: (p) => ({
      subject: `Pay to confirm · ${s(p, "serviceType", "your booking")}`,
      body: {heading: `${s(p, "serviceType", "Your booking")} with ${s(p, "proName", "your pro")}`,
        subheading: `${s(p, "dateLabel")} ${s(p, "timeSlot")}`.trim(),
        paragraphs: [`Pay ${inr(n(p, "total"))} in the Pawgo app to confirm. ` +
          "Unpaid bookings expire on the day of service."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },

  // ---------- woofs ----------
  WOOF1: {
    category: "woofs", essential: false, collapse: false,
    route: "/discover", channels: ["push"],
    render: () => ({title: "It's a match! 🐾", body: "You both woofed. Say hello!"}),
  },

  // ---------- community ----------
  COMM1: {
    category: "community", essential: false, collapse: true,
    route: "/community", channels: ["push"],
    render: (p) => ({title: `${s(p, "authorName", "Someone")} commented on your post`,
      body: s(p, "text").slice(0, 140) || s(p, "postTitle")}),
  },

  // ---------- money (essential) ----------
  PAY1: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `Payment received · ${inr(n(p, "total"))}`,
      body: subject(p)}),
    email: (p) => ({
      subject: `Your Pawgo receipt · ${inr(n(p, "total"))}`,
      body: {heading: s(p, "kind") === "service" ?
        `${s(p, "serviceType", "Service")} with ${s(p, "proName", "your pro")}` :
        `${s(p, "petName", "Your pet")} at ${s(p, "homeName", "the home")}`,
      subheading: s(p, "kind") === "service" ?
        `${s(p, "dateLabel")} ${s(p, "timeSlot")}`.trim() :
        `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")}`,
      rows: receiptLines(p),
      footer: [`Payment ID ${s(p, "paymentId")}`, `Booking ${s(p, "bookingId")}`,
        "Keep this for your records."]},
    }),
  },
  PAY2: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `${inr(n(p, "amount"))} refunded`,
      body: "It'll reach your account in 5–7 working days."}),
    email: (p) => ({
      subject: `Your Pawgo refund · ${inr(n(p, "amount"))}`,
      body: {heading: `${inr(n(p, "amount"))} is on its way back`,
        paragraphs: [`Your cancellation of ${subject(p)} has been refunded. ` +
          "Refunds usually reach your account in 5–7 working days, depending on your bank."],
        footer: [`Refund ID ${s(p, "refundId")}`, `Booking ${s(p, "bookingId")}`]},
    }),
  },
  PAY3: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: "Cancelled — no refund due",
      body: `${subject(p)} was cancelled too late for a refund.`}),
    email: (p) => ({
      subject: "Your Pawgo cancellation",
      body: {heading: "Cancelled — no refund due",
        paragraphs: [`${subject(p)} has been cancelled.`,
          "Our policy refunds cancellations made before the day itself, so nothing " +
          "is coming back on this one. Nothing further will be charged."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  PAY4: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `${inr(n(p, "amount"))} sent to your bank`,
      body: "Your Pawgo earnings are on the way."}),
    email: (p) => ({
      subject: `Payout sent · ${inr(n(p, "amount"))}`,
      body: {heading: `${inr(n(p, "amount"))} is on its way to your bank`,
        paragraphs: ["Bank transfers usually land within 1–2 working days."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  PAY5: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `${inr(n(p, "amount"))} in earnings waiting`,
      body: "Add your bank details to get paid."}),
    email: (p) => ({
      subject: `${inr(n(p, "amount"))} waiting — add your bank details`,
      body: {heading: `You've earned ${inr(n(p, "amount"))}`,
        paragraphs: ["We can't send it until we know where to send it. " +
          "Add your bank details in Pawgo under Payments and we'll transfer " +
          "everything you're owed on the next payout run."]},
    }),
  },

  // ---------- account (essential) ----------
  ACC1: {
    category: "account", essential: true, collapse: false,
    route: "/profile", channels: ["push", "email"],
    render: () => ({title: "You're Pawgo-verified ✅",
      body: "Your ID check passed. The verified badge is now on your listing."}),
    email: () => ({
      subject: "You're verified on Pawgo",
      body: {heading: "Your ID check passed",
        paragraphs: ["The verified badge now shows on your listing. " +
          "Verified partners get noticeably more bookings."]},
    }),
  },
  ACC2: {
    category: "account", essential: true, collapse: false,
    route: "/profile", channels: ["push", "email"],
    render: (p) => ({title: "Your ID check didn't pass",
      body: s(p, "reason", "Please submit your documents again.")}),
    email: (p) => ({
      subject: "Your Pawgo ID check needs another look",
      body: {heading: "We couldn't verify your documents",
        paragraphs: [s(p, "reason", "Please submit your documents again."),
          "You can re-submit from your profile in the Pawgo app. " +
          "Your listing stays live in the meantime, just without the verified badge."]},
    }),
  },

  // ---------- reminders (push-only) ----------
  REM1: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "Pay today or this booking expires",
      body: `${s(p, "serviceType", "Your booking")} with ${s(p, "proName", "your pro")} · today`}),
  },
  REM2: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "Pay to confirm your stay",
      body: `${s(p, "petName", "Your pet")} checks in tomorrow at ${s(p, "homeName", "the home")}.`}),
  },
  REM3: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "Appointment tomorrow",
      body: `${s(p, "serviceType", "Booking")} · ${s(p, "petName", "your pet")} · ${s(p, "timeSlot")}`}),
  },
  REM4: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: `${s(p, "petName", "Your pet")} checks in tomorrow`,
      body: `${s(p, "homeName", "The home")} · ${n(p, "nights")} nights`}),
  },
  REM5: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "How was it?",
      body: `Leave ${s(p, "proName", s(p, "homeName", "them"))} a review — it takes 10 seconds.`}),
  },
};
```

- [ ] **Step 4: Run the tests and the build**

Run: `npm --prefix functions test`
Expected: PASS — all catalogue tests, including the two refund-wording assertions

Run: `npm --prefix functions run build`
Expected: exit 0

- [ ] **Step 5: Commit**

```bash
git add functions/src/notify/catalog.ts functions/src/notify/catalog.test.ts
git commit -m "feat: notification scenario catalogue (25 scenarios, push + email)"
```

---

### Task 3: `notify()` — the single send path

**Files:**
- Create: `functions/src/notify/notify.ts`
- Create: `functions/src/notify/notify.test.ts`

**Interfaces:**
- Consumes: `CATALOG`, `PREF_FIELD`, `ScenarioId`, `P` from `./catalog`; `sendEmail` from `./email`.
- Produces: `notify(args: NotifyArgs): Promise<void>` where `NotifyArgs = {scenario: ScenarioId; uid: string; key: string; params?: P; apiKey?: string; from?: string; email?: string}`; `setNotifyDeps(d: Partial<NotifyDeps>): void` and `resetNotifyDeps(): void` for tests.

Dependency injection is deliberate: `notify()` touches Firestore, FCM and Resend, none of which exist in a unit test. A small injectable `deps` object keeps the logic testable without the emulator.

- [ ] **Step 1: Write the failing test**

Create `functions/src/notify/notify.test.ts`:

```ts
import {describe, it, expect, beforeEach, afterEach} from "vitest";
import {notify, setNotifyDeps, resetNotifyDeps} from "./notify";

type Written = {path: string; data: Record<string, unknown>; existed: boolean};

let written: Written[];
let pushed: {uid: string; title: string; tokens: string[]}[];
let emailed: {to: string; subject: string}[];
let profile: Record<string, unknown>;
let tokens: string[];
let existingKeys: Set<string>;

beforeEach(() => {
  written = []; pushed = []; emailed = [];
  profile = {}; tokens = ["tok1"]; existingKeys = new Set();
  setNotifyDeps({
    readProfile: async () => profile,
    readTokens: async () => tokens,
    writeRecord: async (uid, key, data, collapse) => {
      const path = `${uid}/${key}`;
      const existed = existingKeys.has(path);
      if (existed && !collapse) return false;
      existingKeys.add(path);
      written.push({path, data, existed});
      return true;
    },
    sendPush: async (uid, title, body, route, toks) => {
      pushed.push({uid, title, tokens: toks});
      void body; void route;
      return [];
    },
    pruneTokens: async () => undefined,
    sendMail: async (_k, _f, to, subject) => {
      emailed.push({to, subject});
      return true;
    },
    verifiedEmail: async () => "user@example.com",
  });
});

const base = {uid: "u1", key: "k1", apiKey: "re_real", from: "Pawgo <a@b.com>"};

describe("notify", () => {
  it("writes a record, pushes, and emails a push+email scenario", async () => {
    await notify({...base, scenario: "PAY1", params: {kind: "service", total: 440}});
    expect(written).toHaveLength(1);
    expect(written[0].data.scenario).toBe("PAY1");
    expect(written[0].data.category).toBe("money");
    expect(written[0].data.read).toBe(false);
    expect(pushed).toHaveLength(1);
    expect(emailed).toHaveLength(1);
  });

  it("suppresses push when the category preference is off", async () => {
    profile = {notifyBookings: false};
    await notify({...base, scenario: "BOOK4", params: {}});
    expect(pushed).toHaveLength(0);
  });

  it("still writes the record when the preference suppresses the push", async () => {
    profile = {notifyBookings: false};
    await notify({...base, scenario: "BOOK4", params: {}});
    expect(written).toHaveLength(1);
  });

  it("never lets a preference suppress email", async () => {
    profile = {notifyBookings: false};
    await notify({...base, scenario: "BOOK4", params: {}});
    expect(emailed).toHaveLength(1);
  });

  it("sends essential push even with every preference off", async () => {
    profile = {notifyMoney: false, notifyAccount: false, notifyBookings: false};
    await notify({...base, scenario: "ACC1", params: {}});
    expect(pushed).toHaveLength(1);
  });

  it("treats an absent preference field as ON", async () => {
    profile = {};
    await notify({...base, scenario: "REM4", params: {}});
    expect(pushed).toHaveLength(1);
  });

  it("does not resend on a redelivered event", async () => {
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(written).toHaveLength(1);
    expect(pushed).toHaveLength(1);
    expect(emailed).toHaveLength(1);
  });

  it("re-pushes a collapsing scenario but keeps one record", async () => {
    await notify({...base, scenario: "MSG1", key: "chat_c1", params: {text: "hi"}});
    await notify({...base, scenario: "MSG1", key: "chat_c1", params: {text: "again"}});
    expect(pushed).toHaveLength(2);
    expect(written.filter((w) => w.path === "u1/chat_c1")).toHaveLength(2);
  });

  it("sends no push for an email-only scenario", async () => {
    await notify({...base, scenario: "BOOK9", params: {}});
    expect(pushed).toHaveLength(0);
    expect(emailed).toHaveLength(1);
  });

  it("still pushes when email fails", async () => {
    setNotifyDeps({sendMail: async () => {
      throw new Error("resend down");
    }});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(pushed).toHaveLength(1);
  });

  it("still emails when push throws", async () => {
    setNotifyDeps({sendPush: async () => {
      throw new Error("fcm down");
    }});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(emailed).toHaveLength(1);
  });

  it("skips push when the user has no device tokens", async () => {
    tokens = [];
    await notify({...base, scenario: "REM4", params: {}});
    expect(pushed).toHaveLength(0);
  });

  it("skips email when there is no verified address", async () => {
    setNotifyDeps({verifiedEmail: async () => ""});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(emailed).toHaveLength(0);
  });

  it("does nothing at all for an empty uid", async () => {
    await notify({...base, uid: "", scenario: "PAY1", params: {}});
    expect(written).toHaveLength(0);
    expect(pushed).toHaveLength(0);
  });

  it("never throws when the record write fails", async () => {
    setNotifyDeps({writeRecord: async () => {
      throw new Error("firestore down");
    }});
    await expect(notify({...base, scenario: "PAY1", params: {}})).resolves.toBeUndefined();
  });

  afterEach(() => resetNotifyDeps());
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL — `Cannot find module './notify'`

- [ ] **Step 3: Write `notify()`**

Create `functions/src/notify/notify.ts`:

```ts
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {CATALOG, PREF_FIELD, type P, type Scenario, type ScenarioId} from "./catalog";
import {sendEmail, type EmailBody} from "./email";

/** Everything with a side effect, injectable so the logic is unit-testable
 *  without Firestore, FCM or Resend. Production values are below. */
export type NotifyDeps = {
  readProfile: (uid: string) => Promise<Record<string, unknown>>;
  readTokens: (uid: string) => Promise<string[]>;
  /** Returns false when the record already existed and the scenario does not
   *  collapse — the caller then skips both channels. This is what makes an
   *  at-least-once redelivery harmless. */
  writeRecord: (uid: string, key: string, data: Record<string, unknown>,
    collapse: boolean) => Promise<boolean>;
  /** Resolves to the list of tokens FCM permanently rejected. */
  sendPush: (uid: string, title: string, body: string, route: string,
    tokens: string[]) => Promise<string[]>;
  pruneTokens: (uid: string, tokens: string[]) => Promise<void>;
  sendMail: (apiKey: string, from: string, to: string, subject: string,
    body: EmailBody) => Promise<boolean>;
  verifiedEmail: (uid: string) => Promise<string>;
};

const production: NotifyDeps = {
  readProfile: async (uid) =>
    (await admin.firestore().collection("users").doc(uid).get()).data() ?? {},

  readTokens: async (uid) => (await admin.firestore()
    .collection("users").doc(uid).collection("fcmTokens").get()).docs.map((d) => d.id),

  writeRecord: async (uid, key, data, collapse) => {
    const ref = admin.firestore()
      .collection("notifications").doc(uid).collection("items").doc(key);
    if (collapse) {
      await ref.set(data);
      return true;
    }
    try {
      await ref.create(data); // fails if the doc exists — our dedupe guard
      return true;
    } catch {
      logger.info("notification already sent, skipping", {uid, key});
      return false;
    }
  },

  sendPush: async (uid, title, body, route, tokens) => {
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title, body},
      data: {route},
      android: {priority: "high", notification: {channelId: "pawgo_default"}},
    });
    const dead: string[] = [];
    res.responses.forEach((r, i) => {
      const code = r.error?.code ?? "";
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token") dead.push(tokens[i]);
    });
    logger.info("push sent", {uid, sent: res.successCount, dead: dead.length});
    return dead;
  },

  pruneTokens: async (uid, tokens) => {
    const db = admin.firestore();
    await Promise.all(tokens.map((t) => db.collection("users").doc(uid)
      .collection("fcmTokens").doc(t).delete().catch(() => undefined)));
  },

  sendMail: (apiKey, from, to, subject, body) => sendEmail(apiKey, from, to, subject, body),

  verifiedEmail: async (uid) => {
    try {
      const u = await admin.auth().getUser(uid);
      return u.emailVerified && u.email ? u.email : "";
    } catch (e) {
      logger.error("verifiedEmail failed", {uid, error: e});
      return "";
    }
  },
};

let deps: NotifyDeps = {...production};
export const setNotifyDeps = (d: Partial<NotifyDeps>) => {
  deps = {...deps, ...d};
};
export const resetNotifyDeps = () => {
  deps = {...production};
};

export type NotifyArgs = {
  scenario: ScenarioId;
  uid: string;
  /** Deterministic dedupe key. Becomes the document id. */
  key: string;
  params?: P;
  apiKey?: string;
  from?: string;
  /** Override the recipient address. Omit to use the verified auth address —
   *  which is what every production caller should do. */
  email?: string;
};

/**
 * The only way anything in Pawgo notifies anyone.
 *
 * Order matters: the record is written FIRST and regardless of preferences.
 * Muting a category opts you out of interruption, not information — your
 * booking history must not vanish from the feed because you turned off push.
 * The record doubles as the send-once guard for both channels.
 *
 * Never throws. A notification that fails must not roll back the booking,
 * message or payment that triggered it.
 */
export async function notify(args: NotifyArgs): Promise<void> {
  const {scenario, uid, key} = args;
  if (!uid || !key) return;
  const spec = CATALOG[scenario];
  if (!spec) return; // unreachable: CATALOG is a typed map
  const params = args.params ?? {};

  let rendered;
  try {
    rendered = spec.render(params);
  } catch (e) {
    logger.error("notification render failed", {scenario, uid, error: e});
    return;
  }

  let fresh = true;
  try {
    fresh = await deps.writeRecord(uid, key, {
      scenario,
      category: spec.category,
      title: rendered.title,
      body: rendered.body,
      route: spec.route,
      createdAt: Date.now(),
      read: false,
    }, spec.collapse);
  } catch (e) {
    // Losing the feed row is bad; losing the notification entirely is worse.
    logger.error("notification record write failed", {scenario, uid, key, error: e});
  }
  if (!fresh) return;

  // The two channels are independent: neither failure may suppress the other.
  await Promise.all([
    spec.channels.includes("push") ? pushIfAllowed(args, spec, rendered) : undefined,
    spec.channels.includes("email") ? mail(args, spec, params) : undefined,
  ]);
}

async function pushIfAllowed(
  args: NotifyArgs,
  spec: Scenario,
  rendered: {title: string; body: string},
) {
  try {
    if (!spec.essential) {
      const profile = await deps.readProfile(args.uid);
      // Absent means ON: accounts predating a flag must not go quiet.
      if (profile[PREF_FIELD[spec.category]] === false) {
        logger.info("push suppressed by preference", {uid: args.uid, category: spec.category});
        return;
      }
    }
    const tokens = await deps.readTokens(args.uid);
    if (tokens.length === 0) return;
    const dead = await deps.sendPush(
      args.uid, rendered.title, rendered.body, spec.route, tokens);
    if (dead.length) await deps.pruneTokens(args.uid, dead);
  } catch (e) {
    logger.error("push failed", {scenario: args.scenario, uid: args.uid, error: e});
  }
}

async function mail(args: NotifyArgs, spec: Scenario, params: P) {
  try {
    if (!spec.email) return;
    const to = args.email ?? await deps.verifiedEmail(args.uid);
    if (!to) return;
    const {subject, body} = spec.email(params);
    await deps.sendMail(args.apiKey ?? "", args.from ?? "", to, subject, body);
  } catch (e) {
    logger.error("email failed", {scenario: args.scenario, uid: args.uid, error: e});
  }
}
```

- [ ] **Step 4: Run the tests and the build**

Run: `npm --prefix functions test`
Expected: PASS — all 16 notify tests

Run: `npm --prefix functions run build`
Expected: exit 0

- [ ] **Step 5: Commit**

```bash
git add functions/src/notify/notify.ts functions/src/notify/notify.test.ts
git commit -m "feat: notify() single send path with per-channel isolation"
```

---

### Task 4: Move the six existing triggers onto `notify()`

Behaviour-preserving refactor. Nothing new sends; `sendPushTo` and its six callers leave `index.ts`. Do this **before** adding scenarios so the new ones land in a clean module.

**Files:**
- Create: `functions/src/notify/triggers.ts`
- Create: `functions/src/notify/mask.ts` (moved out of `index.ts`)
- Create: `functions/src/notify/mask.test.ts`
- Modify: `functions/src/index.ts` (delete `PushCategory`/`PREF_FIELD`/`sendPushTo` at lines 78–130; delete `onChatMessageCreated`, `onHomestayBookingWritten`, `onHomestayBookingCreated`, `onServiceBookingWritten`, `onSwipeCreated` at lines 166–305; move `maskContactDetails` to `notify/mask.ts` and re-export it; delete the `sendPushTo` call at the end of `onReviewCreated`)
- Create: `functions/src/notify/keys.ts`
- Create: `functions/src/notify/keys.test.ts`

**Interfaces:**
- Consumes: `notify` from `./notify`.
- Produces: `maskContactDetails(text: string): string` from `./mask`.

> **Why `maskContactDetails` moves.** `triggers.ts` needs it, and `index.ts` will
> `export * from "./notify/triggers"`. Importing it back from `../index` would
> make the two modules circular. It resolves at call time under CommonJS so it
> would probably work — "probably" is not a good property for the code that
> stops phone numbers leaking in chat. Moving it to a leaf module removes the
> cycle entirely. `index.ts` re-exports it so its public name is unchanged.
- Produces: `functions/src/notify/keys.ts` exporting `bookingKey(scenario: string, bookingId: string): string`, `chatKey(chatId: string): string`, `postKey(postId: string): string`, `matchKey(otherUid: string): string`, `monthKey(scenario: string, at: number): string`, `verdictKey(scenario: string, reviewedAt: number): string`. `triggers.ts` re-exports the five trigger constants unchanged in name so `index.ts` can `export * from "./notify/triggers"`.

- [ ] **Step 1: Write the failing key test**

Create `functions/src/notify/keys.test.ts`:

```ts
import {describe, it, expect} from "vitest";
import {bookingKey, chatKey, postKey, matchKey, monthKey, verdictKey} from "./keys";

describe("dedupe keys", () => {
  it("are stable across calls", () => {
    expect(bookingKey("BOOK4", "bk1")).toBe(bookingKey("BOOK4", "bk1"));
  });

  it("distinguish scenarios on the same booking", () => {
    expect(bookingKey("BOOK4", "bk1")).not.toBe(bookingKey("BOOK6", "bk1"));
  });

  it("distinguish bookings within a scenario", () => {
    expect(bookingKey("BOOK4", "bk1")).not.toBe(bookingKey("BOOK4", "bk2"));
  });

  it("build the documented shapes", () => {
    expect(bookingKey("REM4", "bk1")).toBe("REM4_bk1");
    expect(chatKey("c1")).toBe("chat_c1");
    expect(postKey("p1")).toBe("post_p1");
    expect(matchKey("u2")).toBe("WOOF1_u2");
    expect(verdictKey("ACC1", 1753500000000)).toBe("ACC1_1753500000000");
  });

  it("buckets monthly keys by IST calendar month", () => {
    // 2026-08-01T01:00+05:30 is still July in UTC — must bucket as August.
    const istAug1 = Date.parse("2026-08-01T01:00:00+05:30");
    expect(monthKey("PAY5", istAug1)).toBe("PAY5_2026-08");
    const istJul31 = Date.parse("2026-07-31T23:00:00+05:30");
    expect(monthKey("PAY5", istJul31)).toBe("PAY5_2026-07");
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL — `Cannot find module './keys'`

- [ ] **Step 3: Write the keys module**

Create `functions/src/notify/keys.ts`:

```ts
/** Deterministic dedupe keys. The key becomes the notification document id, so
 *  a re-delivered trigger re-writes the same path instead of notifying twice.
 *  Keys are scoped per user (records live under notifications/{uid}/items), so
 *  a scenario sent to two people can safely share one key. */

export const bookingKey = (scenario: string, bookingId: string) => `${scenario}_${bookingId}`;
export const chatKey = (chatId: string) => `chat_${chatId}`;
export const postKey = (postId: string) => `post_${postId}`;
export const matchKey = (otherUid: string) => `WOOF1_${otherUid}`;
export const verdictKey = (scenario: string, reviewedAt: number) =>
  `${scenario}_${reviewedAt}`;

/** IST calendar month. Bucketing in UTC would move the boundary by 5.5 hours
 *  and let a 1am-IST run on the 1st count as the previous month. */
export const monthKey = (scenario: string, at: number) => {
  const ist = new Date(at + 5.5 * 3600 * 1000);
  const mm = String(ist.getUTCMonth() + 1).padStart(2, "0");
  return `${scenario}_${ist.getUTCFullYear()}-${mm}`;
};
```

- [ ] **Step 4: Run the key test**

Run: `npm --prefix functions test`
Expected: PASS

- [ ] **Step 4b: Move `maskContactDetails` into a leaf module**

Create `functions/src/notify/mask.ts` by moving the block from `functions/src/index.ts` lines 132–160 verbatim — the doc comment, the three regexes and the function:

```ts
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
```

Delete that block from `index.ts` and add near its other imports:

```ts
import {maskContactDetails} from "./notify/mask";
export {maskContactDetails};
```

Create `functions/src/notify/mask.test.ts` — this logic had no unit test before:

```ts
import {describe, it, expect} from "vitest";
import {maskContactDetails} from "./mask";

describe("maskContactDetails", () => {
  it("masks a plain phone number", () => {
    expect(maskContactDetails("call me on 9876543210")).toBe("call me on ••••");
  });

  it("masks a spaced and punctuated number", () => {
    expect(maskContactDetails("+91 98765-43210")).toBe("••••");
  });

  it("masks emails and URLs", () => {
    expect(maskContactDetails("a@b.com")).toBe("••••");
    expect(maskContactDetails("see www.foo.com")).toBe("see ••••");
  });

  it("leaves ordinary short numbers alone", () => {
    expect(maskContactDetails("I'm on floor 2, flat 301")).toBe("I'm on floor 2, flat 301");
  });

  it("leaves innocent text untouched", () => {
    expect(maskContactDetails("See you at 5")).toBe("See you at 5");
  });
});
```

Run: `npm --prefix functions test`
Expected: PASS — 5 mask tests

- [ ] **Step 5: Create `triggers.ts` with the five migrated triggers**

Create `functions/src/notify/triggers.ts`:

```ts
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {notify} from "./notify";
import {bookingKey, chatKey, matchKey} from "./keys";
import {maskContactDetails} from "./mask";
import {MAIL_FROM} from "./email";

const REGION = "asia-south1";
const resendApiKey = defineSecret("RESEND_API_KEY");

/** Every email-capable trigger needs the secret bound and the sender passed. */
const mail = () => ({apiKey: resendApiKey.value(), from: MAIL_FROM});

const fmtDay = (iso: string) => {
  const d = new Date(`${String(iso).slice(0, 10)}T00:00:00+05:30`);
  return Number.isFinite(d.getTime()) ?
    d.toLocaleDateString("en-IN", {weekday: "short", day: "numeric", month: "short",
      timeZone: "Asia/Kolkata"}) : String(iso);
};

/** A new chat message notifies the other participant — never someone who has
 *  blocked the sender, which would hand a blocked user a way to keep reaching
 *  into their notification tray.
 *
 *  Also enforces contact masking: the client's maskPhones is a courtesy, and
 *  anyone using the SDK directly bypasses it. */
export const onChatMessageCreated = onDocumentCreated(
  {region: REGION, document: "chats/{chatId}/messages/{messageId}"},
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;
    const senderId = String(msg.senderId ?? "");
    const db = admin.firestore();

    const original = String(msg.text ?? "");
    const masked = maskContactDetails(original);
    let text = original;
    if (masked !== original) {
      text = masked;
      try {
        await event.data!.ref.update({text: masked, masked: true});
        await db.collection("chats").doc(event.params.chatId).update({lastMessage: masked});
      } catch (e) {
        logger.error("contact masking failed to persist",
          {chatId: event.params.chatId, error: e});
      }
    }

    const chat = (await db.collection("chats").doc(event.params.chatId).get()).data();
    if (!chat) return;
    const recipient = (chat.participants as string[] ?? []).find((p) => p !== senderId);
    if (!recipient) return;

    const blocked = await db.collection("users").doc(recipient)
      .collection("blocked").doc(senderId).get();
    if (blocked.exists) return;

    await notify({
      scenario: "MSG1", uid: recipient, key: chatKey(event.params.chatId),
      params: {senderName: (chat.names ?? {})[senderId] ?? "Someone", text},
    });
  });

/** Homestay lifecycle. The host learns about payment or a cancellation; the
 *  guest learns the host's decision. */
export const onHomestayBookingWritten = onDocumentUpdated(
  {region: REGION, document: "homestayBookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const id = event.params.id;
    const p = {
      petName: after.petName, homeName: after.homeName, nights: after.nights,
      total: after.total, subtotal: after.subtotal,
      checkInLabel: fmtDay(String(after.checkIn ?? "")),
      checkOutLabel: fmtDay(String(after.checkOut ?? "")),
    };
    const guestId = String(after.guestId ?? "");
    const hostId = String(after.hostId ?? "");

    switch (after.status) {
    case "accepted":
      await notify({scenario: "BOOK4", uid: guestId, key: bookingKey("BOOK4", id),
        params: p, ...mail()});
      break;
    case "declined":
      await notify({scenario: "BOOK5", uid: guestId, key: bookingKey("BOOK5", id),
        params: p, ...mail()});
      break;
    case "paid":
      await notify({scenario: "BOOK6", uid: hostId, key: bookingKey("BOOK6", id),
        params: p, ...mail()});
      break;
    case "cancelled":
      await notify({scenario: "BOOK7", uid: hostId, key: bookingKey("BOOK7", id),
        params: p, ...mail()});
      break;
    }
  });

export const onHomestayBookingCreated = onDocumentCreated(
  {region: REGION, document: "homestayBookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const b = event.data?.data();
    if (!b || b.status !== "requested") return;
    const id = event.params.id;
    const p = {
      petName: b.petName, homeName: b.homeName, nights: b.nights,
      total: b.total, subtotal: b.subtotal,
      checkInLabel: fmtDay(String(b.checkIn ?? "")),
      checkOutLabel: fmtDay(String(b.checkOut ?? "")),
      bookingId: id,
    };
    // The host must act; the guest gets a written record of what they sent.
    await notify({scenario: "BOOK3", uid: String(b.hostId ?? ""),
      key: bookingKey("BOOK3", id), params: p, ...mail()});
    await notify({scenario: "BOOK9", uid: String(b.guestId ?? ""),
      key: bookingKey("BOOK9", id), params: p, ...mail()});
  });

/** Service bookings: the pro is told when money has landed ('confirmed') and
 *  when a customer cancels and frees the slot. A freshly created but unpaid
 *  booking is deliberately silent for the pro — they have nothing to act on
 *  until it is paid. BOOK10 tells the CUSTOMER, who does. */
export const onServiceBookingWritten = onDocumentUpdated(
  {region: REGION, document: "bookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const id = event.params.id;
    const p = {
      petName: after.petName, serviceType: after.serviceType, proName: after.proName,
      dateLabel: after.dateLabel, timeSlot: after.timeSlot, bookingId: id,
    };
    if (after.status === "confirmed") {
      await notify({scenario: "BOOK1", uid: String(after.proId ?? ""),
        key: bookingKey("BOOK1", id), params: p, ...mail()});
    } else if (after.status === "cancelled") {
      await notify({scenario: "BOOK2", uid: String(after.proId ?? ""),
        key: bookingKey("BOOK2", id), params: p, ...mail()});
    }
  });

/** A reciprocal Woof is the payoff moment of Discover, and neither side sees it
 *  unless they happen to be in the deck — so both get told. */
export const onSwipeCreated = onDocumentCreated(
  {region: REGION, document: "swipes/{id}"},
  async (event) => {
    const swipe = event.data?.data();
    if (!swipe || swipe.direction !== "woof") return;
    const fromUid = String(swipe.fromUid ?? "");
    const ownerId = String(swipe.ownerId ?? "");
    if (!fromUid || !ownerId || fromUid === ownerId) return;

    const reciprocal = await admin.firestore().collection("swipes")
      .where("fromUid", "==", ownerId)
      .where("ownerId", "==", fromUid)
      .where("direction", "==", "woof")
      .limit(1).get();
    if (reciprocal.empty) return;

    await Promise.all([
      notify({scenario: "WOOF1", uid: fromUid, key: matchKey(ownerId)}),
      notify({scenario: "WOOF1", uid: ownerId, key: matchKey(fromUid)}),
    ]);
  });
```

- [ ] **Step 6: Strip the old push code from `index.ts`**

In `functions/src/index.ts`:

1. Delete the `PushCategory` type, the `PREF_FIELD` constant and the whole `sendPushTo` function (currently lines 78–130, ending at the closing brace after the `logger.info("sendPushTo", …)` line), along with the doc comment block above them that begins `/** Sends one notification to every device a user is signed in on.`
2. Delete the five trigger exports `onChatMessageCreated`, `onHomestayBookingWritten`, `onHomestayBookingCreated`, `onServiceBookingWritten` and `onSwipeCreated` (currently lines 166–305).
3. In `onReviewCreated`, delete the trailing push block — the `const stars = …` line and the `await sendPushTo(targetId, …)` call — and replace it with:

```ts
    await notify({
      scenario: "BOOK8", uid: targetId, key: bookingKey("BOOK8", event.params.bookingId),
      params: {stars: Number(review.stars) || 0, text: String(review.text ?? ""),
        authorName: review.authorName ?? "Someone"},
    });
```

4. Add to the imports at the top:

```ts
import {notify} from "./notify/notify";
import {bookingKey} from "./notify/keys";
```

5. Add at the very bottom of the file so the trigger names stay exported from the same entry point:

```ts
export * from "./notify/triggers";
```

6. Confirm `maskContactDetails` now lives only in `notify/mask.ts` and is re-exported from `index.ts` (Step 4b) — there must be no `import … from "../index"` anywhere under `notify/`.

- [ ] **Step 7: Verify the build and full test run**

Run: `npm --prefix functions run build`
Expected: exit 0. If it reports an unused `logger` or `admin` import in `index.ts`, remove only the genuinely unused ones.

Run: `npm --prefix functions test`
Expected: PASS — all tests from Tasks 1–3 plus the key tests

- [ ] **Step 8: Commit**

```bash
git add functions/src/index.ts functions/src/notify/triggers.ts functions/src/notify/keys.ts functions/src/notify/keys.test.ts
git commit -m "refactor: move the six push triggers onto notify(); add BOOK9"
```

---

### Task 5: Payment, refund and community scenarios

Wires `PAY1`, `PAY2`, `PAY3`, `BOOK10` and `COMM1`, and deletes the two defective inline email calls.

**Files:**
- Modify: `functions/src/index.ts` (`verifyBookingPayment` receipt block ~lines 474–502; `refundBookingPayment` email block ~lines 888–901)
- Modify: `functions/src/notify/triggers.ts` (add `onCommentCreated`, `onServiceBookingCreated`)
- Delete: the now-unused `sendInvoiceEmail`/`sendRefundEmail` exports from `functions/src/invoice.ts`, keeping `MAIL_DISABLED` and `isMailConfigured`
- Modify: `functions/src/notify/catalog.test.ts` (no change needed — the wording assertions already cover this)

**Interfaces:**
- Consumes: `notify`, `bookingKey`, `postKey` from Task 3/4.
- Produces: triggers `onCommentCreated`, `onServiceBookingCreated`.

- [ ] **Step 1: Replace the receipt block in `verifyBookingPayment`**

In `functions/src/index.ts`, replace the entire `try { … } catch (e) { logger.error("verifyBookingPayment: receipt email failed", …) }` block with:

```ts
    // Receipt — push AND email, both owned by the catalogue. Never allowed to
    // throw: the money has moved and the booking is confirmed, so a mail or
    // FCM outage must not surface to the user as a failed payment.
    try {
      const b = (await ref.get()).data() ?? {};
      const p = amounts.parts;
      await notify({
        scenario: "PAY1", uid, key: `PAY1_${paymentId}`,
        apiKey: resendApiKey.value(), from: MAIL_FROM,
        params: {
          kind, bookingId, paymentId, total: amounts.total,
          rate: p.rate, fee: p.fee, subtotal: p.subtotal, nights: p.nights,
          serviceType: b.serviceType, proName: b.proName,
          dateLabel: b.dateLabel, timeSlot: b.timeSlot,
          petName: b.petName, homeName: b.homeName,
          checkInLabel: String(b.checkIn ?? ""), checkOutLabel: String(b.checkOut ?? ""),
        },
      });
    } catch (e) {
      logger.error("verifyBookingPayment: receipt notification failed", {bookingId, error: e});
    }
```

- [ ] **Step 2: Replace the refund email block in `refundBookingPayment`**

The current call sits **inside** `if (claim.refundAmount > 0)`, which is why a ₹0 refund sends nothing. Move it out. Replace the `try { const b = …; await sendRefundEmail(…); } catch (…) {}` block inside the `if` with nothing, and insert this immediately **before** the closing `return {refundAmount: claim.refundAmount, refundId};`:

```ts
    // Confirmation regardless of amount. A same-day cancellation refunds ₹0 —
    // which is exactly when someone most wants to be told, in writing, why no
    // money is coming back.
    try {
      const b = (await ref.get()).data() ?? {};
      const paid = claim.refundAmount > 0;
      await notify({
        scenario: paid ? "PAY2" : "PAY3",
        uid,
        key: `${paid ? "PAY2" : "PAY3"}_${bookingId}`,
        apiKey: resendApiKey.value(), from: MAIL_FROM,
        params: {
          kind, bookingId, refundId, amount: claim.refundAmount,
          serviceType: b.serviceType, proName: b.proName, homeName: b.homeName,
        },
      });
    } catch (e) {
      logger.error("refundBookingPayment: notification failed", {bookingId, error: e});
    }
```

- [ ] **Step 3: Remove the dead email helpers**

In `functions/src/invoice.ts`, delete `InvoiceInput`, `InvoiceLine`, `invoiceHtml`, `invoiceText`, `sendInvoiceEmail` and `sendRefundEmail`, along with the now-unused `Resend`, `logger`, `inr` and `esc` bindings. The file keeps only:

```ts
/// Placeholder written to Secret Manager so the codebase can deploy before a
/// Resend account exists — the CLI refuses to deploy ANY function while a
/// declared secret has no value, even ones that don't use it. Treated as "email
/// is off" rather than firing doomed API calls on every payment.
export const MAIL_DISABLED = "unset";

export const isMailConfigured = (apiKey: string) =>
  apiKey.length > 0 && apiKey !== MAIL_DISABLED;
```

In `functions/src/index.ts`, delete the whole `import {sendInvoiceEmail, sendRefundEmail, InvoiceLine} from "./invoice";` line — nothing in `index.ts` uses any of it once the two blocks above are replaced. Also delete `index.ts`'s own `const MAIL_FROM = …` declaration and import it instead, so the sender address exists in exactly one place:

```ts
import {MAIL_FROM} from "./notify/email";
```

- [ ] **Step 4: Add the two new triggers**

Append to `functions/src/notify/triggers.ts`:

```ts
/** A comment on someone's post. Collapses per post — a busy thread must not
 *  become twenty feed rows — but still pushes on every comment. */
export const onCommentCreated = onDocumentCreated(
  {region: REGION, document: "posts/{postId}/comments/{commentId}"},
  async (event) => {
    const c = event.data?.data();
    if (!c) return;
    const authorId = String(c.authorId ?? "");
    const post = (await admin.firestore()
      .collection("posts").doc(event.params.postId).get()).data();
    if (!post) return;
    const postAuthor = String(post.authorId ?? "");
    // Commenting on your own post notifies nobody.
    if (!postAuthor || postAuthor === authorId) return;

    const blocked = await admin.firestore().collection("users").doc(postAuthor)
      .collection("blocked").doc(authorId).get();
    if (blocked.exists) return;

    await notify({
      scenario: "COMM1", uid: postAuthor, key: postKey(event.params.postId),
      params: {authorName: c.authorName ?? "Someone", text: String(c.body ?? ""),
        postTitle: post.title ?? ""},
    });
  });

/** An unpaid service booking. Email-only, to the CUSTOMER: they are looking at
 *  a confirmation screen right now, so a push telling them what they just did
 *  is noise — but the email is the record they'll search for later. */
export const onServiceBookingCreated = onDocumentCreated(
  {region: REGION, document: "bookings/{id}", secrets: [resendApiKey]},
  async (event) => {
    const b = event.data?.data();
    if (!b || b.status !== "pending") return;
    const id = event.params.id;
    await notify({
      scenario: "BOOK10", uid: String(b.parentId ?? ""), key: bookingKey("BOOK10", id),
      ...mail(),
      params: {serviceType: b.serviceType, proName: b.proName, dateLabel: b.dateLabel,
        timeSlot: b.timeSlot, total: b.total, bookingId: id},
    });
  });
```

Add `postKey` to the existing keys import at the top of `triggers.ts`:

```ts
import {bookingKey, chatKey, matchKey, postKey} from "./keys";
```

- [ ] **Step 5: Verify the build and tests**

Run: `npm --prefix functions run build`
Expected: exit 0

Run: `npm --prefix functions test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add functions/src/index.ts functions/src/invoice.ts functions/src/notify/triggers.ts
git commit -m "feat: PAY1/PAY2/PAY3/BOOK10/COMM1; fix refund email wording and the silent zero-refund"
```

---

### Task 6: KYC verdicts and payout notifications

**Files:**
- Modify: `functions/src/notify/triggers.ts` (add `onVerificationReviewed`)
- Modify: `functions/src/index.ts` (`processPayouts`, the release loop ~lines 606–620)

**Interfaces:**
- Consumes: `notify`, `verdictKey`, `bookingKey`.
- Produces: trigger `onVerificationReviewed`.

- [ ] **Step 1: Add the verification trigger**

Append to `functions/src/notify/triggers.ts`:

```ts
/** The admin panel's verdict on a KYC submission. Until now the panel flipped
 *  `verified` and the partner was told nothing — so approval was invisible and
 *  rejection looked like the feature was broken. Essential category: a partner
 *  who muted notifications still needs to know their ID check failed. */
export const onVerificationReviewed = onDocumentUpdated(
  {region: REGION, document: "verificationRequests/{uid}", secrets: [resendApiKey]},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    if (after.status !== "approved" && after.status !== "rejected") return;

    const scenario = after.status === "approved" ? "ACC1" : "ACC2";
    const reviewedAt = Number(after.reviewedAt ?? Date.now());
    await notify({
      scenario, uid: event.params.uid, key: verdictKey(scenario, reviewedAt),
      ...mail(),
      params: {reason: String(after.reason ?? "")},
    });
  });
```

Add `verdictKey` to the keys import in `triggers.ts`:

```ts
import {bookingKey, chatKey, matchKey, postKey, verdictKey} from "./keys";
```

- [ ] **Step 2: Notify on payout release**

In `functions/src/index.ts`, inside `processPayouts`, in the "2. Release held transfers" loop, replace this line:

```ts
        await setStatus(doc.ref, "released", {releasedAt: Date.now(), error: ""});
```

with:

```ts
        await setStatus(doc.ref, "released", {releasedAt: Date.now(), error: ""});
        await notify({
          scenario: "PAY4", uid: String(p.partnerId ?? ""), key: `PAY4_${doc.id}`,
          apiKey: resendApiKey.value(), from: MAIL_FROM,
          params: {amount: Number(p.amount ?? 0), bookingId: String(p.bookingId ?? "")},
        });
```

Then add `resendApiKey` to the `processPayouts` secrets so the value is available:

```ts
  {region: REGION, schedule: "every day 02:00", timeZone: "Asia/Kolkata",
    secrets: [razorpayKeyId, razorpayKeySecret, resendApiKey]},
```

- [ ] **Step 3: Verify the build and tests**

Run: `npm --prefix functions run build`
Expected: exit 0

Run: `npm --prefix functions test`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add functions/src/index.ts functions/src/notify/triggers.ts
git commit -m "feat: ACC1/ACC2 KYC verdicts and PAY4 payout-released notifications"
```

---

### Task 7: `dailyNotifications` — reminders, the payout sweep and retention

**Files:**
- Create: `functions/src/notify/reminders.ts`
- Create: `functions/src/notify/reminders.test.ts`
- Modify: `functions/src/index.ts` (add `export * from "./notify/reminders";`)
- Modify: `firestore.indexes.json`

**Interfaces:**
- Consumes: `notify`, `bookingKey`, `monthKey`.
- Produces: `istDay(at: number, offsetDays: number): string`; the scheduled Function `dailyNotifications`.

- [ ] **Step 1: Write the failing date test**

Create `functions/src/notify/reminders.test.ts`:

```ts
import {describe, it, expect} from "vitest";
import {istDay} from "./reminders";

describe("istDay", () => {
  it("returns today in IST for offset 0", () => {
    const at = Date.parse("2026-07-26T09:00:00+05:30");
    expect(istDay(at, 0)).toBe("2026-07-26");
  });

  it("returns tomorrow for offset 1 and yesterday for -1", () => {
    const at = Date.parse("2026-07-26T09:00:00+05:30");
    expect(istDay(at, 1)).toBe("2026-07-27");
    expect(istDay(at, -1)).toBe("2026-07-25");
  });

  it("uses the IST calendar day, not the UTC one", () => {
    // 04:00 IST on the 27th is 22:30 UTC on the 26th. UTC maths would answer
    // "2026-07-26" here, and every reminder would fire a day late.
    const at = Date.parse("2026-07-27T04:00:00+05:30");
    expect(istDay(at, 0)).toBe("2026-07-27");
  });

  it("crosses a month boundary", () => {
    const at = Date.parse("2026-07-31T09:00:00+05:30");
    expect(istDay(at, 1)).toBe("2026-08-01");
  });

  it("crosses a year boundary", () => {
    const at = Date.parse("2026-12-31T09:00:00+05:30");
    expect(istDay(at, 1)).toBe("2027-01-01");
  });

  it("handles a leap day", () => {
    const at = Date.parse("2028-02-28T09:00:00+05:30");
    expect(istDay(at, 1)).toBe("2028-02-29");
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL — `Cannot find module './reminders'`

- [ ] **Step 3: Write the scheduled job**

Create `functions/src/notify/reminders.ts`:

```ts
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
```

- [ ] **Step 4: Export it and add the indexes**

Add to the bottom of `functions/src/index.ts`, next to the triggers export:

```ts
export * from "./notify/reminders";
```

Replace `firestore.indexes.json` with:

```json
{
  "indexes": [
    {
      "collectionGroup": "swipes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "fromUid", "order": "ASCENDING" },
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "direction", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "bookings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "date", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "homestayBookings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "checkIn", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "homestayBookings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "checkOut", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "items",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "createdAt", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": [
    {
      "collectionGroup": "comments",
      "fieldPath": "authorId",
      "indexes": [
        { "order": "ASCENDING", "queryScope": "COLLECTION" },
        { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }
      ]
    }
  ]
}
```

- [ ] **Step 5: Verify the build and tests**

Run: `npm --prefix functions test`
Expected: PASS — the six `istDay` tests plus everything prior

Run: `npm --prefix functions run build`
Expected: exit 0

- [ ] **Step 6: Commit**

```bash
git add functions/src/notify/reminders.ts functions/src/notify/reminders.test.ts functions/src/index.ts firestore.indexes.json
git commit -m "feat: dailyNotifications - 5 reminders, PAY5 sweep, 90-day retention"
```

---

### Task 8: Firestore rules for the notifications collection

**Files:**
- Modify: `firestore.rules`

**Interfaces:**
- Produces: the `notifications/{uid}/items/{id}` match block.

- [ ] **Step 1: Add the rule**

In `firestore.rules`, immediately after the closing brace of the `match /users/{uid} { … }` block, insert:

```
    // Server-authored notification records. Read-only to their owner, who may
    // flip `read` and nothing else.
    //
    // No client create: a client that can write one of these can forge "your
    // refund was processed". No client delete: one that can remove them can
    // hide a KYC rejection. The Functions write with the Admin SDK, which
    // bypasses rules entirely.
    match /notifications/{uid}/items/{id} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow update: if request.auth != null && request.auth.uid == uid
                    && request.resource.data.diff(resource.data).affectedKeys()
                         .hasOnly(['read']);
      allow create, delete: if false;
    }
```

- [ ] **Step 2: Verify the rules parse**

Run: `firebase deploy --only firestore:rules --dry-run`
Expected: "rules file compiled successfully". **This does not deploy** — `--dry-run` compiles and stops.

If the Firebase CLI is not on PATH, skip the command and instead verify by eye that the new block sits inside the top-level `match /databases/{database}/documents { … }` and that every brace it opens is closed. The compile happens for real at deploy time.

> **Known deviation from the spec.** The spec's testing section asks for automated
> rules tests (a client cannot create/delete/forge; can set only `read`). This
> repo has **no rules-test harness** — no `@firebase/rules-unit-testing`, no
> emulator wiring — so there is nowhere to put them. Adding that harness is
> real infrastructure (emulator install, a second test runner, CI wiring) and
> does not belong wedged into this slice. The rule above is deliberately
> restrictive by construction (`allow create, delete: if false`), and the
> on-device QA pass exercises it against live rules. **Log this as a follow-up
> slice; do not silently treat the spec's rules-test requirement as met.**

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat: rules for server-authored notification records"
```

---

### Task 9: Client — the notification model, repository and providers

Adds the read side without changing the UI yet. The old derived feed still renders; this task only introduces the new pipe.

**Files:**
- Create: `lib/data/models/notification_record.dart`
- Create: `lib/data/repositories/notification_repository.dart`
- Create: `lib/data/repositories/firebase/firestore_notification_repository.dart`
- Modify: `lib/data/repositories/providers.dart`
- Modify: `test/support/fakes.dart`
- Create: `test/data/notification_record_test.dart`

**Interfaces:**
- Produces: `class NotificationRecord {String id, scenario, category, title, body, route; int createdAt; bool read; factory NotificationRecord.fromMap(String id, Map<String, dynamic> m)}`; `abstract interface class NotificationRepository { Stream<List<NotificationRecord>> watch(String uid); Future<void> markRead(String uid, String id); Future<void> markAllRead(String uid); }`; provider `notificationRepositoryProvider`; `class FakeNotificationRepository implements NotificationRepository`.

- [ ] **Step 1: Write the failing test**

Create `test/data/notification_record_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/notification_record.dart';

void main() {
  test('maps a full document', () {
    final r = NotificationRecord.fromMap('PAY1_pay_123', {
      'scenario': 'PAY1', 'category': 'money',
      'title': 'Payment received · ₹440', 'body': 'Dog walking with Rahul',
      'route': '/payments', 'createdAt': 1753500000000, 'read': false,
    });
    expect(r.id, 'PAY1_pay_123');
    expect(r.scenario, 'PAY1');
    expect(r.category, 'money');
    expect(r.route, '/payments');
    expect(r.createdAt, 1753500000000);
    expect(r.read, isFalse);
  });

  test('survives a document with missing fields', () {
    final r = NotificationRecord.fromMap('x', const {});
    expect(r.title, '');
    expect(r.category, '');
    expect(r.createdAt, 0);
    expect(r.read, isFalse);
  });

  test('read defaults to false when absent', () {
    final r = NotificationRecord.fromMap('x', const {'title': 'Hi'});
    expect(r.read, isFalse);
  });

  test('emoji and accent are derived from the category, not stored', () {
    expect(NotificationRecord.fromMap('a', const {'category': 'messages'}).emoji, '💬');
    expect(NotificationRecord.fromMap('b', const {'category': 'money'}).emoji, '💰');
    expect(NotificationRecord.fromMap('c', const {'category': 'woofs'}).emoji, '🐾');
    // An unknown category must not crash — it falls back to a bell.
    expect(NotificationRecord.fromMap('d', const {'category': 'nonsense'}).emoji, '🔔');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/notification_record_test.dart`
Expected: FAIL — `Target of URI doesn't exist: notification_record.dart`

- [ ] **Step 3: Write the model**

Create `lib/data/models/notification_record.dart`:

```dart
import 'package:flutter/material.dart';

/// One server-authored notification, read from `notifications/{uid}/items`.
///
/// The server stores the rendered `title`/`body` rather than parameters — the
/// catalogue in `functions/src/notify/catalog.ts` is the single source of copy,
/// so the client never re-renders text and the two can never drift.
///
/// Presentation is NOT stored: emoji and accent are derived from `category`
/// here. Putting `0xFF34B27B` in Firestore would be a category error.
class NotificationRecord {
  final String id, scenario, category, title, body, route;
  final int createdAt;
  final bool read;

  const NotificationRecord({
    required this.id, required this.scenario, required this.category,
    required this.title, required this.body, required this.route,
    required this.createdAt, required this.read,
  });

  factory NotificationRecord.fromMap(String id, Map<String, dynamic> m) =>
      NotificationRecord(
        id: id,
        scenario: (m['scenario'] ?? '') as String,
        category: (m['category'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        route: (m['route'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
        read: (m['read'] ?? false) as bool,
      );

  static const _emoji = {
    'messages': '💬', 'bookings': '🗓️', 'woofs': '🐾', 'community': '💬',
    'reminders': '⏰', 'money': '💰', 'account': '✅',
  };

  static const _accent = {
    'messages': Color(0xFF6B8DE0), 'bookings': Color(0xFF34B27B),
    'woofs': Color(0xFFF59E2E), 'community': Color(0xFF8B5CF6),
    'reminders': Color(0xFFF97316), 'money': Color(0xFF34B27B),
    'account': Color(0xFF34B27B),
  };

  String get emoji => _emoji[category] ?? '🔔';
  Color get accent => _accent[category] ?? const Color(0xFF9AA0A6);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/notification_record_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 5: Add the repository interface and Firestore implementation**

Create `lib/data/repositories/notification_repository.dart`:

```dart
import '../models/notification_record.dart';

abstract interface class NotificationRepository {
  /// Newest first. Capped server-side — the feed is a rolling window.
  Stream<List<NotificationRecord>> watch(String uid);
  Future<void> markRead(String uid, String id);
  Future<void> markAllRead(String uid);
}
```

Create `lib/data/repositories/firebase/firestore_notification_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notification_record.dart';
import '../notification_repository.dart';

class FirestoreNotificationRepository implements NotificationRepository {
  final FirebaseFirestore _db;
  FirestoreNotificationRepository([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

  @override
  Stream<List<NotificationRecord>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs
            .map((d) => NotificationRecord.fromMap(d.id, d.data()))
            .toList());
  }

  /// Rules allow the owner to change `read` and nothing else.
  @override
  Future<void> markRead(String uid, String id) =>
      _items(uid).doc(id).update({'read': true});

  @override
  Future<void> markAllRead(String uid) async {
    final unread = await _items(uid).where('read', isEqualTo: false).limit(400).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}
```

- [ ] **Step 6: Register the provider**

In `lib/data/repositories/providers.dart`, add these imports next to the existing repository imports:

```dart
import 'notification_repository.dart';
import 'firebase/firestore_notification_repository.dart';
import '../models/notification_record.dart';
```

And add this provider immediately above the existing `notificationsProvider`:

```dart
final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => FirestoreNotificationRepository());
```

- [ ] **Step 7: Add the fake**

Append to `test/support/fakes.dart`:

```dart
class FakeNotificationRepository implements NotificationRepository {
  final _controller = StreamController<List<NotificationRecord>>.broadcast();
  List<NotificationRecord> records;

  FakeNotificationRepository([this.records = const []]);

  void emit(List<NotificationRecord> next) {
    records = next;
    _controller.add(next);
  }

  @override
  Stream<List<NotificationRecord>> watch(String uid) async* {
    yield records;
    yield* _controller.stream;
  }

  @override
  Future<void> markRead(String uid, String id) async {
    emit([
      for (final r in records)
        if (r.id == id)
          NotificationRecord(
            id: r.id, scenario: r.scenario, category: r.category,
            title: r.title, body: r.body, route: r.route,
            createdAt: r.createdAt, read: true)
        else
          r,
    ]);
  }

  @override
  Future<void> markAllRead(String uid) async {
    emit([
      for (final r in records)
        NotificationRecord(
          id: r.id, scenario: r.scenario, category: r.category,
          title: r.title, body: r.body, route: r.route,
          createdAt: r.createdAt, read: true),
    ]);
  }
}
```

Add the imports `dart:async`, `package:pet_aggregator_app/data/models/notification_record.dart` and `package:pet_aggregator_app/data/repositories/notification_repository.dart` to the top of `test/support/fakes.dart` if they are not already present.

- [ ] **Step 8: Verify green**

Run: `flutter analyze`
Expected: No issues found

Run: `flutter test`
Expected: all tests pass (the old feed is untouched)

- [ ] **Step 9: Commit**

```bash
git add lib/data/models/notification_record.dart lib/data/repositories/notification_repository.dart lib/data/repositories/firebase/firestore_notification_repository.dart lib/data/repositories/providers.dart test/support/fakes.dart test/data/notification_record_test.dart
git commit -m "feat: NotificationRecord model + repository + fake"
```

---

### Task 10: Client — swap the feed off `buildNotifications`

The migration. Every user's feed starts empty and refills from the first new event; that is acceptable only because no build has shipped.

**Files:**
- Modify: `lib/data/repositories/providers.dart` (`notificationsProvider`, `hasUnreadNotificationsProvider`)
- Modify: `lib/features/notifications/notifications_screen.dart`
- Delete: `lib/features/notifications/notification_item.dart`
- Modify: `lib/data/models/user_profile.dart` (remove `notifsSeenAt`)
- Modify: `lib/data/repositories/user_repository.dart` + `lib/data/repositories/firebase/firestore_user_repository.dart` (remove `markNotificationsSeen`)
- Modify: `test/support/fakes.dart` (remove `markNotificationsSeen` from the fake)
- Delete: `test/features/notifications_builder_test.dart`, `test/features/notifications_lifecycle_test.dart`, `test/features/notifications_paid_test.dart`
- Modify: `test/features/notifications_screen_test.dart`
- Modify: `test/features/home_bell_test.dart` (it reads `hasUnreadNotificationsProvider`)

**Interfaces:**
- Consumes: `notificationRepositoryProvider`, `NotificationRecord`, `FakeNotificationRepository` from Task 9.
- Produces: `notificationsProvider` as `StreamProvider<List<NotificationRecord>>`; `hasUnreadNotificationsProvider` as `Provider<bool>`.

- [ ] **Step 1: Write the failing screen test**

Replace `test/features/notifications_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/notification_record.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/notifications/notifications_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

NotificationRecord _rec(String id,
        {String title = 'Payment received',
        String category = 'money',
        bool read = false,
        int createdAt = 1000}) =>
    NotificationRecord(
      id: id, scenario: 'PAY1', category: category, title: title,
      body: 'Dog walking with Rahul', route: '/payments',
      createdAt: createdAt, read: read);

void main() {
  testWidgets('renders records from the repository', (t) async {
    final repo = FakeNotificationRepository([_rec('a'), _rec('b', title: 'Refunded')]);
    await pumpPgApp(t, const NotificationsScreen(), overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets('shows the empty state when there is nothing', (t) async {
    await pumpPgApp(t, const NotificationsScreen(), overrides: [
      notificationRepositoryProvider.overrideWithValue(FakeNotificationRepository()),
    ]);
    await t.pumpAndSettle();
    expect(find.textContaining("You're all caught up"), findsOneWidget);
  });

  testWidgets('email-only scenarios still appear in the feed', (t) async {
    final repo = FakeNotificationRepository([
      _rec('c', title: 'Stay request sent', category: 'bookings'),
    ]);
    await pumpPgApp(t, const NotificationsScreen(), overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Stay request sent'), findsOneWidget);
  });

  testWidgets('Mark all read hides the affordance and clears unread', (t) async {
    final repo = FakeNotificationRepository([_rec('a'), _rec('b')]);
    await pumpPgApp(t, const NotificationsScreen(), overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
    await t.tap(find.text('Mark all read'));
    await t.pumpAndSettle();
    expect(repo.records.every((r) => r.read), isTrue);
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('no Mark all read affordance when everything is read', (t) async {
    final repo = FakeNotificationRepository([_rec('a', read: true)]);
    await pumpPgApp(t, const NotificationsScreen(), overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Mark all read'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/notifications_screen_test.dart`
Expected: FAIL — `notificationRepositoryProvider` is not yet consumed by the screen

- [ ] **Step 3: Rewrite the providers**

In `lib/data/repositories/providers.dart`, replace `notificationsProvider` and `hasUnreadNotificationsProvider` with:

```dart
/// Server-authored notification records, newest first.
///
/// Replaces the old client-side derivation: push, email and this feed are now
/// written by one call in the Cloud Functions, so they cannot disagree — and
/// scenarios with no client-readable source (a KYC verdict, a released payout,
/// a reminder) can appear here at all.
final notificationsProvider = StreamProvider<List<NotificationRecord>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid ?? '';
  if (uid.isEmpty) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(uid);
});

final hasUnreadNotificationsProvider = Provider<bool>((ref) =>
    (ref.watch(notificationsProvider).value ?? const <NotificationRecord>[])
        .any((n) => !n.read));
```

Delete the now-unused import of `../../features/notifications/notification_item.dart`.

- [ ] **Step 4: Rewrite the screen**

Replace `lib/features/notifications/notifications_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/notification_record.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final items = ref.watch(notificationsProvider).value ?? const <NotificationRecord>[];
    final hasUnread = items.any((n) => !n.read);
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.chevron_left, color: c.text))),
              const SizedBox(width: 14),
              Expanded(child: Text('Notifications',
                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
              if (hasUnread)
                GestureDetector(
                  onTap: () =>
                      ref.read(notificationRepositoryProvider).markAllRead(myUid),
                  child: Text('Mark all read',
                    style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
            ]),
          ),
          Expanded(child: items.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text("You're all caught up — no notifications yet.",
                  textAlign: TextAlign.center,
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                itemCount: items.length,
                itemBuilder: (_, i) => _NotifRow(item: items[i], myUid: myUid),
              )),
        ]),
      ),
    );
  }
}

class _NotifRow extends ConsumerWidget {
  final NotificationRecord item;
  final String myUid;
  const _NotifRow({required this.item, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (!item.read) {
          await ref.read(notificationRepositoryProvider).markRead(myUid, item.id);
        }
        if (!context.mounted || item.route.isEmpty) return;
        context.go(item.route);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: item.read ? c.surface : c.brandSoft,
          border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13)),
            child: Text(item.emoji, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: PgText.inter(13.5, FontWeight.w700, color: c.text)),
            const SizedBox(height: 2),
            Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 4),
            Text(Post.timeAgo(item.createdAt),
              style: PgText.inter(11, FontWeight.w400, color: c.muted)),
          ])),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: Delete the derivation and its dead state**

1. Delete `lib/features/notifications/notification_item.dart`.
2. Delete `test/features/notifications_builder_test.dart`, `test/features/notifications_lifecycle_test.dart` and `test/features/notifications_paid_test.dart` — they test the deleted function. Their behaviour is now covered by the catalogue and `notify()` tests on the server.
3. In `lib/data/models/user_profile.dart`, remove the `notifsSeenAt` field from the class, from `toMap`, from `fromMap` and from `copyWith`.
4. Remove `markNotificationsSeen` from `lib/data/repositories/user_repository.dart`, from `lib/data/repositories/firebase/firestore_user_repository.dart`, and from the fake user repository in `test/support/fakes.dart`.

- [ ] **Step 6: Fix the remaining references**

Run: `flutter analyze`

Fix every error it reports. Expect references in `test/features/home_bell_test.dart` (which overrides `hasUnreadNotificationsProvider` or seeds the old providers) and any `notifsSeenAt` usages. For `home_bell_test.dart`, seed unread state by overriding `notificationRepositoryProvider` with a `FakeNotificationRepository` holding one unread record instead of the old profile field.

Expected once fixed: No issues found

- [ ] **Step 7: Run the tests**

Run: `flutter test`
Expected: all pass

- [ ] **Step 8: Commit**

```bash
git add -A lib/features/notifications lib/data/repositories/providers.dart lib/data/models/user_profile.dart lib/data/repositories/user_repository.dart lib/data/repositories/firebase/firestore_user_repository.dart test/support/fakes.dart test/features
git commit -m "feat: read the notification feed from the server; delete buildNotifications"
```

---

### Task 11: Settings — five toggles and the essential tier

**Files:**
- Modify: `lib/data/models/user_profile.dart` (`NotificationPrefs`)
- Modify: `lib/features/profile/settings_screen.dart`
- Modify: `test/features/notification_prefs_test.dart`

**Interfaces:**
- Produces: `NotificationPrefs` with `messages`, `bookings`, `woofs`, `community`, `reminders`, all defaulting `true`, mapping to `notifyMessages`/`notifyBookings`/`notifyWoofs`/`notifyCommunity`/`notifyReminders`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/notification_prefs_test.dart`:

```dart
  test('community and reminders default to ON when absent', () {
    final p = NotificationPrefs.fromMap(const {});
    expect(p.community, isTrue);
    expect(p.reminders, isTrue);
  });

  test('round-trips all five flags', () {
    const p = NotificationPrefs(
        messages: false, bookings: true, woofs: false,
        community: false, reminders: true);
    final back = NotificationPrefs.fromMap(p.toMap());
    expect(back.messages, isFalse);
    expect(back.bookings, isTrue);
    expect(back.woofs, isFalse);
    expect(back.community, isFalse);
    expect(back.reminders, isTrue);
  });

  test('copyWith touches only the named flag', () {
    const p = NotificationPrefs();
    expect(p.copyWith(community: false).community, isFalse);
    expect(p.copyWith(community: false).reminders, isTrue);
  });
```

And add this widget test in the same file (inside `void main()`):

```dart
  testWidgets('renders five toggles and an always-on essential row', (t) async {
    await pumpPgApp(t, const SettingsScreen());
    await t.pumpAndSettle();
    expect(find.text('New messages'), findsOneWidget);
    expect(find.text('Booking updates'), findsOneWidget);
    expect(find.text('New Woofs & matches'), findsOneWidget);
    expect(find.text('Community replies'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Payments & account'), findsOneWidget);
    expect(find.text('Always on'), findsOneWidget);
  });
```

Add the imports the file needs at the top if absent: `package:pet_aggregator_app/features/profile/settings_screen.dart`, `../support/pump.dart`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/notification_prefs_test.dart`
Expected: FAIL — `community` is not defined

- [ ] **Step 3: Extend `NotificationPrefs`**

In `lib/data/models/user_profile.dart`, replace the whole `NotificationPrefs` class with:

```dart
/// Which push categories a user wants. Read server-side by `notify()` before
/// every push, so turning one off stops the notification at the source rather
/// than hiding it after delivery.
///
/// All five default to **true**, including when the field is absent — existing
/// accounts predate these flags and must not silently go quiet.
///
/// There is deliberately no flag for money or account notifications. Those are
/// the essential tier: a refund that landed or an ID check that failed is a
/// support incident if it goes unsaid, not a preference. Email is likewise
/// never gated — a receipt is a record, not an interruption.
class NotificationPrefs {
  final bool messages, bookings, woofs, community, reminders;
  const NotificationPrefs({
    this.messages = true,
    this.bookings = true,
    this.woofs = true,
    this.community = true,
    this.reminders = true,
  });

  NotificationPrefs copyWith({
    bool? messages, bool? bookings, bool? woofs, bool? community, bool? reminders,
  }) =>
      NotificationPrefs(
        messages: messages ?? this.messages,
        bookings: bookings ?? this.bookings,
        woofs: woofs ?? this.woofs,
        community: community ?? this.community,
        reminders: reminders ?? this.reminders,
      );

  Map<String, dynamic> toMap() => {
        'notifyMessages': messages,
        'notifyBookings': bookings,
        'notifyWoofs': woofs,
        'notifyCommunity': community,
        'notifyReminders': reminders,
      };

  factory NotificationPrefs.fromMap(Map<String, dynamic> m) => NotificationPrefs(
        messages: (m['notifyMessages'] ?? true) as bool,
        bookings: (m['notifyBookings'] ?? true) as bool,
        woofs: (m['notifyWoofs'] ?? true) as bool,
        community: (m['notifyCommunity'] ?? true) as bool,
        reminders: (m['notifyReminders'] ?? true) as bool,
      );
}
```

- [ ] **Step 4: Add the rows to Settings**

In `lib/features/profile/settings_screen.dart`, replace the `Column(children: [...])` inside `_NotificationPrefsCard.build` with:

```dart
      child: Column(children: [
        _toggleRow(c, '💬', 'New messages', 'When someone messages you',
            prefs.messages, (v) => save(prefs.copyWith(messages: v)), border: true),
        _toggleRow(c, '🗓️', 'Booking updates',
            'Requests, confirmations, cancellations & reviews',
            prefs.bookings, (v) => save(prefs.copyWith(bookings: v)), border: true),
        _toggleRow(c, '🐾', 'New Woofs & matches', 'When you and another pet match',
            prefs.woofs, (v) => save(prefs.copyWith(woofs: v)), border: true),
        _toggleRow(c, '💭', 'Community replies', 'When someone comments on your post',
            prefs.community, (v) => save(prefs.copyWith(community: v)), border: true),
        _toggleRow(c, '⏰', 'Reminders',
            'Upcoming bookings, payments due & review prompts',
            prefs.reminders, (v) => save(prefs.copyWith(reminders: v)), border: true),
        _alwaysOnRow(c, '💰', 'Payments & account',
            'Receipts, refunds, payouts & ID verification'),
      ]),
```

And add this method to `_NotificationPrefsCard`, next to `_toggleRow`:

```dart
  /// The essential tier, shown rather than hidden. Silently failing to tell
  /// someone their refund landed or their ID was rejected is a support
  /// incident, not a preference — so this row states the fact instead of
  /// offering a switch that would be a lie.
  Widget _alwaysOnRow(PgColors c, String emoji, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.all(15),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.inter(14, FontWeight.w600, color: c.text)),
            Text(subtitle, style: PgText.inter(12, FontWeight.w400, color: c.muted)),
          ])),
          Text('Always on', style: PgText.inter(12, FontWeight.w600, color: c.muted)),
        ]),
      );
```

Update the doc comment above `class _NotificationPrefsCard` to:

```dart
/// The five controllable push categories, plus the essential tier stated as a
/// fact.
///
/// The prototype's "Nearby pet alerts" row is deliberately absent: there is no
/// nearby-pet notification anywhere in the app, so the switch would control
/// nothing.
```

- [ ] **Step 5: Verify green**

Run: `flutter test test/features/notification_prefs_test.dart`
Expected: PASS

Run: `flutter analyze`
Expected: No issues found

Run: `flutter test`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/user_profile.dart lib/features/profile/settings_screen.dart test/features/notification_prefs_test.dart
git commit -m "feat: Community and Reminders toggles + the always-on essential row"
```

---

### Task 12: Deep-link routes and the final verification pass

**Files:**
- Modify: `lib/features/notifications/push_registrar.dart` (extract `resolveTapRoute`)
- Modify: `lib/core/router/routes.dart` (only if `Routes.profile` is missing)
- Modify: `test/features/push_registrar_test.dart`
- Modify: `left.md`

**Interfaces:**
- Consumes: routes used by the catalogue — `/messages`, `/bookings`, `/discover`, `/community`, `/payments`, `/profile`.

Route resolution is currently inline in `_handleTap`, which calls `context.go` — and the existing `push_registrar_test.dart` pumps a bare `MaterialApp` with no router, so there is nothing there that can assert a navigation. Rather than build router scaffolding for a set-membership check, extract the decision into a pure function and test that directly.

- [ ] **Step 1: Write the failing test**

Append to `test/features/push_registrar_test.dart`, inside `void main()`:

```dart
  group('resolveTapRoute', () {
    test('passes through every route the catalogue can emit', () {
      for (final r in [
        '/messages', '/bookings', '/notifications', '/home',
        '/discover', '/community', '/payments', '/profile',
      ]) {
        expect(resolveTapRoute(r), r, reason: r);
      }
    });

    test('falls back to Notifications for an unknown route', () {
      expect(resolveTapRoute('/nope'), Routes.notifications);
    });

    test('falls back for a null or empty route', () {
      expect(resolveTapRoute(null), Routes.notifications);
      expect(resolveTapRoute(''), Routes.notifications);
    });
  });
```

Add these imports to that file if absent:

```dart
import 'package:pet_aggregator_app/core/router/routes.dart';
```

- [ ] **Step 2: Run to confirm it fails**

Run: `flutter test test/features/push_registrar_test.dart`
Expected: FAIL — `resolveTapRoute` is undefined

- [ ] **Step 3: Extract the pure resolver and extend the allowlist**

In `lib/features/notifications/push_registrar.dart`, add this as a **top-level** function (above the `PushRegistrar` class):

```dart
/// Every route the notification catalogue can emit, and where anything else
/// goes. Pure and top-level so it can be tested without a router: a tapped
/// notification carrying a path the app doesn't have must land somewhere sane
/// rather than crash on a bad route.
String resolveTapRoute(String? route) {
  const known = {
    Routes.bookings, Routes.chatList, Routes.notifications,
    Routes.home, Routes.discover, Routes.community, Routes.payments,
    Routes.profile,
  };
  return known.contains(route) ? route! : Routes.notifications;
}
```

Then replace the body of `_handleTap` with:

```dart
  void _handleTap(Map<String, String> payload) {
    if (!mounted) return;
    context.go(resolveTapRoute(payload['route']));
  }
```

If `Routes.profile` does not exist in `lib/core/router/routes.dart`, add `static const profile = '/profile';` and confirm a route with that path is registered in the router. If a constant with the value `'/profile'` already exists under a different name, use that name instead and adjust the test's expected list to match.

- [ ] **Step 4: Verify the full suite**

Run: `flutter analyze`
Expected: No issues found

Run: `flutter test`
Expected: all pass

Run: `npm --prefix functions run build`
Expected: exit 0

Run: `npm --prefix functions test`
Expected: all pass

- [ ] **Step 5: Update the status doc**

In `left.md`, under "Notifications, email and signup notes", replace the bullet reading **"Push is server-driven; the in-app feed is not."** with:

```markdown
- **Push, email and the in-app feed are one system.** A catalogue of 25 scenarios
  in `functions/src/notify/catalog.ts` is the single source; `notify()` writes a
  record to `notifications/{uid}/items` and then sends push and email. The three
  can no longer drift, and the record doubles as the send-once guard, so a
  redelivered trigger cannot double-notify. `buildNotifications` is deleted.
- **Reminders exist.** `dailyNotifications` runs at 09:00 IST: pay-or-expire
  nudges, next-day reminders for both pillars, review prompts, a monthly
  "add your bank details" sweep, and 90-day retention on the feed.
- **Email still sends nothing.** `RESEND_API_KEY` is the literal `unset`, so all
  16 email scenarios deploy inert. Push is the only channel that reaches anyone
  until a Resend account and verified domain exist.
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/notifications/push_registrar.dart lib/core/router/routes.dart test/features/push_registrar_test.dart left.md
git commit -m "feat: deep-link routes for the new scenarios; refresh left.md"
```

---

## Deployment note (do NOT run as part of this plan)

When the owner deploys:

```bash
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions
```

`dailyNotifications` is a new scheduled Function and `onCommentCreated`/`onVerificationReviewed` are new event triggers. Per `left.md`, the project's first event-triggered 2nd-gen deploy failed once with an **Eventarc Service Agent** permission error and succeeded on a retry ~4 minutes later with no code change. If that error appears, retry rather than debug.

Nothing reaches a user until a new APK/AAB ships — token registration lives in the client, so no device holds an FCM token yet.
