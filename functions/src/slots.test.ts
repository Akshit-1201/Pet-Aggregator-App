import {describe, expect, it} from "vitest";
import {
  DEFAULT_AVAILABILITY, HOLD_MS, assertBookable, findConflict, isoWeekday, isActive,
  overlaps, parseAvailability, prune, slotOf, slotStartEpoch, type Entry,
} from "./slots";

const booked = (startMin: number, durationMin = 60): Entry =>
  ({startMin, durationMin, status: "booked", heldUntil: 0});
const held = (startMin: number, heldUntil: number, durationMin = 60): Entry =>
  ({startMin, durationMin, status: "held", heldUntil});

describe("overlaps", () => {
  it("treats touching intervals as free (9-10 then 10-11)", () => {
    expect(overlaps(540, 60, 600, 60)).toBe(false);
  });
  it("catches partial and containing overlaps", () => {
    expect(overlaps(540, 60, 570, 60)).toBe(true);
    expect(overlaps(540, 120, 570, 30)).toBe(true);
  });
});

describe("findConflict", () => {
  const now = 1_000_000;
  it("blocks a time already booked", () => {
    expect(findConflict({a: booked(540)}, "me", 540, 60, now)).toBe("a");
  });
  it("blocks a live hold but not a lapsed one", () => {
    expect(findConflict({a: held(540, now + 1)}, "me", 540, 60, now)).toBe("a");
    expect(findConflict({a: held(540, now - 1)}, "me", 540, 60, now)).toBeNull();
  });
  it("ignores the booking's own entry (re-hold on resume)", () => {
    expect(findConflict({me: held(540, now + HOLD_MS)}, "me", 540, 60, now)).toBeNull();
  });
  it("catches overlap across different slot lengths", () => {
    // Pro changed from 60 to 90-minute slots: a 9:00-10:30 booking must block 10:00.
    expect(findConflict({a: booked(540, 90)}, "me", 600, 60, now)).toBe("a");
  });
});

describe("prune / isActive", () => {
  it("keeps bookings forever and drops lapsed holds", () => {
    const now = 5000;
    const out = prune({b: booked(540), h1: held(600, 4000), h2: held(660, 6000)}, now);
    expect(Object.keys(out).sort()).toEqual(["b", "h2"]);
    expect(isActive(booked(1), now)).toBe(true);
  });
});

describe("dates in IST", () => {
  it("knows the ISO weekday", () => {
    expect(isoWeekday("2026-10-12")).toBe(1); // Monday
    expect(isoWeekday("2026-10-18")).toBe(7); // Sunday
  });
  it("anchors slot starts to IST midnight", () => {
    // 2026-10-12 09:00 IST == 03:30 UTC
    expect(new Date(slotStartEpoch("2026-10-12", 540)).toISOString()).toBe("2026-10-12T03:30:00.000Z");
  });
});

describe("assertBookable", () => {
  const avail = parseAvailability({
    weekly: {"1": [{start: 540, end: 720}]}, // Mondays 9:00-12:00 only
    slotMinutes: 60,
  });
  const before = slotStartEpoch("2026-10-12", 0); // well before the slot
  it("accepts an aligned slot inside the window", () => {
    expect(() => assertBookable(avail, "2026-10-12", 600, 60, before)).not.toThrow();
  });
  it("rejects outside the window, misaligned, wrong length, wrong day, or past", () => {
    expect(() => assertBookable(avail, "2026-10-12", 720, 60, before)).toThrow("slot-unavailable");
    expect(() => assertBookable(avail, "2026-10-12", 570, 60, before)).toThrow("slot-unavailable");
    expect(() => assertBookable(avail, "2026-10-12", 600, 30, before)).toThrow("slot-changed");
    expect(() => assertBookable(avail, "2026-10-13", 600, 60, before)).toThrow("slot-unavailable");
    expect(() => assertBookable(avail, "2026-10-12", 600, 60,
      slotStartEpoch("2026-10-12", 600))).toThrow("slot-past");
  });
});

describe("parseAvailability", () => {
  it("defaults when the listing has none, so old pros stay bookable", () => {
    expect(parseAvailability(undefined)).toEqual(DEFAULT_AVAILABILITY);
  });
  it("drops malformed ranges and unknown slot lengths", () => {
    const a = parseAvailability({weekly: {"1": [{start: 600, end: 540}, {start: 60, end: 120}]},
      slotMinutes: 7});
    expect(a.weekly["1"]).toEqual([{start: 60, end: 120}]);
    expect(a.weekly["2"]).toEqual([]);
    expect(a.slotMinutes).toBe(60);
  });
});

describe("slotOf", () => {
  it("skips bookings from builds that predate time slots", () => {
    expect(slotOf({date: "2026-10-12", timeSlot: "5:00 PM"})).toBeNull();
    expect(slotOf({date: "2026-10-12", startMin: 540, durationMin: 60}))
      .toEqual({date: "2026-10-12", startMin: 540, durationMin: 60});
  });
});
