import {describe, it, expect} from "vitest";
import {fmtDay} from "./dates";

describe("fmtDay", () => {
  it("formats a date-only ISO string as a short IST-anchored label", () => {
    expect(fmtDay("2026-08-03")).toBe("Mon, 3 Aug");
  });

  it("ignores any time-of-day component, reading the date at IST midnight", () => {
    expect(fmtDay("2026-08-03T23:59:59Z")).toBe(fmtDay("2026-08-03"));
  });

  it("falls back to the raw string for an unparseable date", () => {
    expect(fmtDay("not-a-date")).toBe("not-a-date");
  });
});
