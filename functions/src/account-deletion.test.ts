import {describe, expect, it} from "vitest";
import {PERSONAL_SUBCOLLECTIONS, personalStoragePrefixes} from "./account-deletion";

const uid = "AbCdEfGhIjKlMnOpQrStUvWxYz12"; // Firebase uids are 28 chars

describe("personalStoragePrefixes", () => {
  it("covers every upload path a user owns that dies with the account", () => {
    expect(personalStoragePrefixes(uid).sort()).toEqual([
      `homestays/${uid}/`, // listing photos — the listing is deleted
      `pets/${uid}_`, // pet photos — the pets are deleted
      `users/${uid}/`, // avatar
      `verification/${uid}/`, // KYC ID documents — the most sensitive files
    ].sort());
  });

  it("keeps post photos, because posts survive anonymised", () => {
    expect(personalStoragePrefixes(uid).some((p) => p.startsWith("posts/"))).toBe(false);
  });

  it("never matches another user's files", () => {
    const other = uid.slice(0, 27) + "X";
    for (const prefix of personalStoragePrefixes(uid)) {
      expect(`pets/${other}_1.jpg`.startsWith(prefix)).toBe(false);
      expect(`verification/${other}/0.jpg`.startsWith(prefix)).toBe(false);
    }
  });

  it("refuses an empty uid rather than returning bucket-wide prefixes", () => {
    expect(() => personalStoragePrefixes("")).toThrow();
  });
});

describe("PERSONAL_SUBCOLLECTIONS", () => {
  // Deleting users/{uid} leaves its subcollections behind in Firestore.
  it("lists the users/{uid} subcollections that must be deleted explicitly", () => {
    expect([...PERSONAL_SUBCOLLECTIONS].sort()).toEqual(["blocked", "fcmTokens"]);
  });
});
