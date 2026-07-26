import {describe, it, expect} from "vitest";
import {bookingKey, scenarioKey, chatKey, postKey, matchKey, monthKey, verdictKey} from "./keys";

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

  it("scenarioKey builds the same shape as bookingKey, for non-booking ids", () => {
    expect(scenarioKey("PAY1", "pay_123")).toBe("PAY1_pay_123");
    expect(scenarioKey("PAY4", "payout_1")).toBe("PAY4_payout_1");
    expect(scenarioKey("PAY1", "x")).toBe(bookingKey("PAY1", "x"));
  });

  it("buckets monthly keys by IST calendar month", () => {
    // 2026-08-01T01:00+05:30 is still July in UTC — must bucket as August.
    const istAug1 = Date.parse("2026-08-01T01:00:00+05:30");
    expect(monthKey("PAY5", istAug1)).toBe("PAY5_2026-08");
    const istJul31 = Date.parse("2026-07-31T23:00:00+05:30");
    expect(monthKey("PAY5", istJul31)).toBe("PAY5_2026-07");
  });
});
