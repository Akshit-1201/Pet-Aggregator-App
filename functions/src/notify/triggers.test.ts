import {describe, it, expect} from "vitest";
import {homestayStatusScenario, serviceBookingStatusScenario} from "./triggers";

describe("homestayStatusScenario", () => {
  it("accepted notifies the guest with BOOK4", () => {
    expect(homestayStatusScenario("requested", "accepted"))
      .toEqual({scenario: "BOOK4", recipient: "guest"});
  });

  it("declined notifies the guest with BOOK5", () => {
    expect(homestayStatusScenario("requested", "declined"))
      .toEqual({scenario: "BOOK5", recipient: "guest"});
  });

  it("paid notifies the host with BOOK6", () => {
    expect(homestayStatusScenario("accepted", "paid"))
      .toEqual({scenario: "BOOK6", recipient: "host"});
  });

  it("cancelled notifies the host with BOOK7", () => {
    expect(homestayStatusScenario("paid", "cancelled"))
      .toEqual({scenario: "BOOK7", recipient: "host"});
  });

  it("an unmapped status ('requested') produces nothing", () => {
    expect(homestayStatusScenario("", "requested")).toBeNull();
  });

  it("a status that did not change produces nothing, even if it's a mapped one", () => {
    // A write that doesn't touch status (e.g. an unrelated field update) must
    // not re-fire "accepted" every time the doc is saved again.
    expect(homestayStatusScenario("accepted", "accepted")).toBeNull();
    expect(homestayStatusScenario("paid", "paid")).toBeNull();
  });
});

describe("serviceBookingStatusScenario", () => {
  it("confirmed notifies the pro with BOOK1", () => {
    expect(serviceBookingStatusScenario("pending", "confirmed"))
      .toEqual({scenario: "BOOK1", recipient: "pro"});
  });

  it("cancelled notifies the pro with BOOK2", () => {
    expect(serviceBookingStatusScenario("confirmed", "cancelled"))
      .toEqual({scenario: "BOOK2", recipient: "pro"});
  });

  it("an unmapped status ('pending') produces nothing", () => {
    expect(serviceBookingStatusScenario("", "pending")).toBeNull();
  });

  it("a status that did not change produces nothing, even if it's a mapped one", () => {
    expect(serviceBookingStatusScenario("confirmed", "confirmed")).toBeNull();
    expect(serviceBookingStatusScenario("cancelled", "cancelled")).toBeNull();
  });
});
