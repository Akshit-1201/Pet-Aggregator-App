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
