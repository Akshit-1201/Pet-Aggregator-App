import {describe, expect, it} from "vitest";
import {SEND_COOLDOWN_MS, SEND_MAX_PER_WINDOW, SEND_WINDOW_MS, nextSendLog, verificationEmailBody} from "./auth-email";
import {renderEmail} from "./notify/email";

describe("verification email", () => {
  const link = "https://pet-aggregator-app.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=abc&x=1";

  it("renders the link as a clickable button, not just text", () => {
    const {html} = renderEmail(verificationEmailBody("Aakarsh Rao", link));
    // The button: an <a> whose visible text is the label, not the URL.
    expect(html).toMatch(/<a href="[^"]*oobCode=abc[^"]*"[^>]*>Verify my email<\/a>/);
  });

  it("escapes the URL so & in the query string stays valid HTML", () => {
    const {html} = renderEmail(verificationEmailBody("A", link));
    expect(html).toContain("oobCode=abc&amp;x=1");
    expect(html).not.toContain("oobCode=abc&x=1\"");
  });

  it("greets by first name and falls back when there is none", () => {
    expect(verificationEmailBody("Aakarsh Rao", link).heading).toBe("Confirm your email, Aakarsh");
    expect(verificationEmailBody("  ", link).heading).toBe("Confirm your email, there");
  });

  it("keeps the link in the plain-text part for text-only clients", () => {
    const {text} = renderEmail(verificationEmailBody("A", link));
    expect(text).toContain(`Verify my email: ${link}`);
  });

  it("is branded Pawgo Pets", () => {
    const {html, text} = renderEmail(verificationEmailBody("A", link));
    expect(html).toContain("Pawgo Pets");
    expect(text.startsWith("Pawgo Pets")).toBe(true);
  });
});

describe("verification send cooldown", () => {
  const t0 = 1_000_000_000;
  it("allows the first send", () => {
    expect(nextSendLog(undefined, t0)).toEqual({lastSentAt: t0, windowStart: t0, count: 1});
  });
  it("refuses a second send within a minute", () => {
    const log = nextSendLog(undefined, t0)!;
    expect(nextSendLog(log, t0 + SEND_COOLDOWN_MS - 1)).toBeNull();
    expect(nextSendLog(log, t0 + SEND_COOLDOWN_MS)).not.toBeNull();
  });
  it("caps sends per day, then resets the next day", () => {
    let log = nextSendLog(undefined, t0)!;
    let t = t0;
    for (let i = 1; i < SEND_MAX_PER_WINDOW; i++) {
      t += SEND_COOLDOWN_MS;
      log = nextSendLog(log, t)!;
    }
    expect(log.count).toBe(SEND_MAX_PER_WINDOW);
    expect(nextSendLog(log, t + SEND_COOLDOWN_MS)).toBeNull();
    expect(nextSendLog(log, t0 + SEND_WINDOW_MS)?.count).toBe(1);
  });
});
