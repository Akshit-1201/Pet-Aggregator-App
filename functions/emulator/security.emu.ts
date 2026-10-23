/**
 * Security regression tests that need a real Firestore — run against the local
 * emulator, never production:
 *
 *   npm run test:emulator
 *
 * Covers the fixes from the security review of the time-slot / moderation
 * release: photo URLs confined to our Storage bucket, and the per-customer
 * slot-hold limit.
 */
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {afterAll, beforeAll, beforeEach, describe, expect, it} from "vitest";
import {
  assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, setDoc} from "firebase/firestore";
import * as admin from "firebase-admin";
import {holdSlot, slotStartEpoch, scheduleId, type Entry} from "../src/slots";

const PROJECT = "demo-pawgo-security";
const OURS = "https://firebasestorage.googleapis.com/v0/b/pet-aggregator-app.firebasestorage.app/o/" +
  "pets%2Fu1_1784405241668.jpg?alt=media&token=5cf3d0b0";
const EVIL = "https://attacker.example/pixel.jpg";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

describe("photo URLs must point into our bucket", () => {
  const db = () => env.authenticatedContext("u1").firestore();

  it("pets: our URL ok, a foreign URL refused (single and in the list)", async () => {
    const pet = {ownerId: "u1", name: "Bruno"};
    await assertSucceeds(setDoc(doc(db(), "pets/p1"), {...pet, photoUrl: OURS, photoUrls: [OURS]}));
    await assertFails(setDoc(doc(db(), "pets/p2"), {...pet, photoUrl: EVIL}));
    await assertFails(setDoc(doc(db(), "pets/p3"), {...pet, photoUrls: [OURS, EVIL]}));
    await assertSucceeds(setDoc(doc(db(), "pets/p4"), {...pet, photoUrl: ""})); // no photo
  });

  it("pets: an existing pet can't be switched to a foreign URL", async () => {
    await assertSucceeds(setDoc(doc(db(), "pets/p1"), {ownerId: "u1", photoUrl: OURS}));
    await assertFails(setDoc(doc(db(), "pets/p1"), {ownerId: "u1", photoUrl: EVIL}));
  });

  it("posts, homestays and the user's own avatar are covered too", async () => {
    await assertFails(setDoc(doc(db(), "posts/x"), {authorId: "u1", photoUrl: EVIL}));
    await assertSucceeds(setDoc(doc(db(), "posts/y"), {authorId: "u1", photoUrl: OURS}));
    await assertFails(setDoc(doc(db(), "homestays/u1"), {photoUrls: [EVIL]}));
    await assertSucceeds(setDoc(doc(db(), "homestays/u1"), {photoUrls: [OURS, OURS, OURS]}));
    await assertFails(setDoc(doc(db(), "users/u1"), {name: "A", photoUrl: EVIL}));
    await assertSucceeds(setDoc(doc(db(), "users/u1"), {name: "A", photoUrl: OURS}));
  });

  it("a lookalike host or another bucket is refused", async () => {
    const pet = {ownerId: "u1"};
    for (const bad of [
      "https://firebasestorage.googleapis.com.attacker.example/v0/b/pet-aggregator-app.firebasestorage.app/o/x",
      "https://firebasestorage.googleapis.com/v0/b/someone-else.appspot.com/o/x.jpg",
      "http://firebasestorage.googleapis.com/v0/b/pet-aggregator-app.firebasestorage.app/o/x.jpg",
    ]) {
      await assertFails(setDoc(doc(db(), `pets/${encodeURIComponent(bad).slice(-20)}`), {...pet, photoUrl: bad}));
    }
  });

  it("the server-only collections are closed to clients", async () => {
    await assertFails(setDoc(doc(db(), "slotHolds/u1"), {bookingId: "b"}));
    await assertFails(setDoc(doc(db(), "verificationSends/u1"), {count: 0}));
  });
});

describe("slot holds: one live hold per customer", () => {
  const date = "2030-01-07"; // a Monday, safely in the future
  const now = slotStartEpoch(date, 0) - 86_400_000;
  const db = () => admin.firestore();
  const booking = (parentId: string, startMin: number) =>
    ({parentId, proId: "pro1", date, startMin, durationMin: 60, status: "pending"});
  const slots = async () =>
    ((await db().collection("proSchedule").doc(scheduleId("pro1", date)).get()).data()?.slots ??
      {}) as Record<string, Entry>;

  beforeEach(async () => {
    await db().collection("pros").doc("pro1").set({name: "Aarav", rate: 250}); // default hours
  });

  it("an unverified account can't hold a slot", async () => {
    await expect(holdSlot(db(), "b1", booking("A", 540), {verified: false}, now))
      .rejects.toThrow("unverified");
    expect(await slots()).toEqual({});
  });

  it("holding a second slot releases the first — a script can't hoard slots", async () => {
    await holdSlot(db(), "a1", booking("A", 540), {verified: true}, now);
    await holdSlot(db(), "a2", booking("A", 600), {verified: true}, now);
    await holdSlot(db(), "a3", booking("A", 660), {verified: true}, now);
    expect(Object.keys(await slots())).toEqual(["a3"]);

    // So another customer can now take the time A held first.
    await holdSlot(db(), "b1", booking("B", 540), {verified: true}, now);
    expect(Object.keys(await slots()).sort()).toEqual(["a3", "b1"]);
  });

  it("re-holding the same booking keeps it (resume after a lapsed payment)", async () => {
    await holdSlot(db(), "a1", booking("A", 540), {verified: true}, now);
    await holdSlot(db(), "a1", booking("A", 540), {verified: true}, now + 60_000);
    expect(Object.keys(await slots())).toEqual(["a1"]);
  });

  it("a confirmed booking is never released by a later hold", async () => {
    await db().collection("proSchedule").doc(scheduleId("pro1", date)).set({
      slots: {a1: {startMin: 540, durationMin: 60, status: "booked", heldUntil: 0}},
    });
    await db().collection("slotHolds").doc("A").set({bookingId: "a1", proId: "pro1", date});
    await holdSlot(db(), "a2", booking("A", 600), {verified: true}, now);
    expect(Object.keys(await slots()).sort()).toEqual(["a1", "a2"]);
  });

  it("a slot held by someone else is still refused", async () => {
    await holdSlot(db(), "a1", booking("A", 540), {verified: true}, now);
    await expect(holdSlot(db(), "b1", booking("B", 540), {verified: true}, now))
      .rejects.toThrow("slot-taken");
  });
});
