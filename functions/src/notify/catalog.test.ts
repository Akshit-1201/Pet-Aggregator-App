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
