import {describe, expect, it} from "vitest";
import {verificationEmailBody} from "./auth-email";
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
