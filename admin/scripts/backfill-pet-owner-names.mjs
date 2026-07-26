/**
 * One-off backfill: `pets.ownerName`.
 *
 * Pets created before the denormalisation have no `ownerName`, so the screens
 * that show whose pet it is fall back to a placeholder — `users/{uid}` is
 * owner-read-only, which is why the name is stored on the pet at all.
 *
 * Idempotent: skips pets that already have a name, and pets whose owner's
 * profile is gone (a deleted account) rather than writing an empty string.
 *
 *   node scripts/backfill-pet-owner-names.mjs          # dry run
 *   node scripts/backfill-pet-owner-names.mjs --apply  # write
 */
import {readFileSync} from "node:fs";
import {cert, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

const apply = process.argv.includes("--apply");

const env = {};
for (const line of readFileSync(new URL("../.env.local", import.meta.url), "utf8").split("\n")) {
  const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
  if (!m) continue;
  let v = m[2].trim();
  if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
  env[m[1]] = v;
}
initializeApp({
  credential: cert({
    projectId: env.FIREBASE_PROJECT_ID,
    clientEmail: env.FIREBASE_CLIENT_EMAIL,
    privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
  }),
});
const db = getFirestore();

const pets = await db.collection("pets").get();
const names = new Map(); // uid -> name, so each owner is read once

let filled = 0;
let already = 0;
let skipped = 0;

for (const pet of pets.docs) {
  const data = pet.data();
  if (String(data.ownerName ?? "").trim()) {
    already++;
    continue;
  }
  const ownerId = String(data.ownerId ?? "");
  if (!ownerId) {
    skipped++;
    continue;
  }
  if (!names.has(ownerId)) {
    const snap = await db.collection("users").doc(ownerId).get();
    names.set(ownerId, String(snap.data()?.name ?? "").trim());
  }
  const name = names.get(ownerId);
  if (!name) {
    console.log(`  skip ${pet.id} (${data.name ?? "?"}) — owner profile missing or unnamed`);
    skipped++;
    continue;
  }
  console.log(`  ${apply ? "set " : "would set"} ${pet.id} (${data.name ?? "?"}) -> "${name}"`);
  if (apply) await pet.ref.update({ownerName: name});
  filled++;
}

console.log(
  `\n${pets.size} pets: ${filled} ${apply ? "updated" : "to update"}, ` +
    `${already} already had a name, ${skipped} skipped.`,
);
if (!apply && filled > 0) console.log("Dry run — re-run with --apply to write.");
process.exit(0);
