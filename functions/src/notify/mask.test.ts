import {describe, it, expect} from "vitest";
import {maskContactDetails} from "./mask";

describe("maskContactDetails", () => {
  it("masks a plain phone number", () => {
    expect(maskContactDetails("call me on 9876543210")).toBe("call me on ••••");
  });

  it("masks a spaced and punctuated number", () => {
    expect(maskContactDetails("+91 98765-43210")).toBe("••••");
  });

  it("masks emails and URLs", () => {
    expect(maskContactDetails("a@b.com")).toBe("••••");
    expect(maskContactDetails("see www.foo.com")).toBe("see ••••");
  });

  it("leaves ordinary short numbers alone", () => {
    expect(maskContactDetails("I'm on floor 2, flat 301")).toBe("I'm on floor 2, flat 301");
  });

  it("leaves innocent text untouched", () => {
    expect(maskContactDetails("See you at 5")).toBe("See you at 5");
  });
});
