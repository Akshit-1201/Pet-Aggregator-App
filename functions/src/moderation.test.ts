import {describe, expect, it} from "vitest";
import {isModeratedPath, moderationVerdict, uploaderOf} from "./moderation-rules";

describe("moderationVerdict", () => {
  it("blocks likely adult or violent images", () => {
    expect(moderationVerdict({adult: "LIKELY"}).blocked).toBe(true);
    expect(moderationVerdict({violence: "VERY_LIKELY"}).blocked).toBe(true);
  });
  it("lets ordinary pet photos through", () => {
    expect(moderationVerdict({adult: "VERY_UNLIKELY", violence: "UNLIKELY", racy: "POSSIBLE"}))
      .toEqual({blocked: false, reasons: []});
  });
  it("only blocks racy at VERY_LIKELY, and never on medical (vet photos)", () => {
    expect(moderationVerdict({racy: "LIKELY"}).blocked).toBe(false);
    expect(moderationVerdict({racy: "VERY_LIKELY"}).blocked).toBe(true);
    expect(moderationVerdict({medical: "VERY_LIKELY"}).blocked).toBe(false);
  });
  it("treats missing annotations as safe", () => {
    expect(moderationVerdict({}).blocked).toBe(false);
  });
});

describe("paths", () => {
  it("moderates every public photo path", () => {
    for (const p of ["users/u1/avatar.jpg", "homestays/u1/a.jpg", "pets/u1_123.jpg", "posts/u1_9.jpg",
      "brands/u1/logo_1.jpg", "brands/u1/p_2.jpg"]) {
      expect(isModeratedPath(p)).toBe(true);
    }
  });
  it("never touches private KYC documents", () => {
    expect(isModeratedPath("verification/u1/id.jpg")).toBe(false);
  });
  it("recovers the uploader from each path convention", () => {
    expect(uploaderOf("users/u1/avatar.jpg")).toBe("u1");
    expect(uploaderOf("homestays/u2/x.jpg")).toBe("u2");
    expect(uploaderOf("pets/u3_1700.jpg")).toBe("u3");
    expect(uploaderOf("posts/u4_1700.jpg")).toBe("u4");
    expect(uploaderOf("brands/u5/p_1700.jpg")).toBe("u5");
    expect(uploaderOf("random/file.jpg")).toBeNull();
  });
});
