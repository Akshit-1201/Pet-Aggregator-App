import {describe, it, expect} from "vitest";
import {istDay, sumOwedByPartner} from "./reminders";

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

describe("sumOwedByPartner", () => {
  it("sums multiple owed payouts for one partner into a single total", () => {
    const totals = sumOwedByPartner([
      {partnerId: "p1", amount: 100},
      {partnerId: "p1", amount: 250},
    ]);
    expect(totals.get("p1")).toBe(350);
    expect(totals.size).toBe(1);
  });

  it("keeps two partners separate", () => {
    const totals = sumOwedByPartner([
      {partnerId: "p1", amount: 100},
      {partnerId: "p2", amount: 200},
    ]);
    expect(totals.get("p1")).toBe(100);
    expect(totals.get("p2")).toBe(200);
    expect(totals.size).toBe(2);
  });

  it("skips a payout with a missing or empty partnerId, not bucketed under \"\"", () => {
    const totals = sumOwedByPartner([
      {partnerId: "", amount: 100},
      {amount: 50}, // partnerId entirely absent
      {partnerId: "p1", amount: 10},
    ]);
    expect(totals.has("")).toBe(false);
    expect(totals.size).toBe(1);
    expect(totals.get("p1")).toBe(10);
  });

  it("treats a non-numeric or absent amount as 0, not NaN", () => {
    const totals = sumOwedByPartner([
      {partnerId: "p1", amount: "not-a-number"},
      {partnerId: "p1"}, // amount entirely absent
      {partnerId: "p2", amount: 100},
    ]);
    expect(totals.get("p1")).toBe(0);
    expect(Number.isNaN(totals.get("p1"))).toBe(false);
    expect(totals.get("p2")).toBe(100);
  });

  it("returns an empty map for empty input", () => {
    const totals = sumOwedByPartner([]);
    expect(totals.size).toBe(0);
  });
});
