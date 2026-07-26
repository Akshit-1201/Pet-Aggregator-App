import {describe, it, expect} from "vitest";
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
});

describe("sendEmail", () => {
  it("returns false without calling Resend when the key is the placeholder", async () => {
    const ok = await sendEmail("unset", "Pawgo <a@b.com>", "x@y.com", "Subject",
      {heading: "x"});
    expect(ok).toBe(false);
  });

  it("returns false when there is no recipient", async () => {
    const ok = await sendEmail("re_realkey", "Pawgo <a@b.com>", "", "Subject",
      {heading: "x"});
    expect(ok).toBe(false);
  });
});
