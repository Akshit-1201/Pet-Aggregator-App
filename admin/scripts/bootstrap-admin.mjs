/**
 * Creates the first super-admin.
 *
 * Chicken-and-egg: the panel grants roles, but only a super-admin can grant
 * them, and nobody is one yet. This writes that first row directly. Run it once:
 *
 *   node scripts/bootstrap-admin.mjs you@example.com
 *
 * Reads the same credentials as the app (admin/.env.local). After this, add
 * everyone else from the Admins page rather than re-running it.
 */
import {readFileSync} from "node:fs";
import {cert, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

// Minimal .env.local reader — this script runs outside Next, which is what
// normally loads env files.
function loadEnv() {
  try {
    for (const line of readFileSync(new URL("../.env.local", import.meta.url), "utf8").split("\n")) {
      const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
      if (!match) continue;
      let value = match[2].trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      process.env[match[1]] ??= value;
    }
  } catch {
    // No .env.local — fall back to whatever is already in the environment.
  }
}

loadEnv();

const email = process.argv[2]?.trim().toLowerCase();
if (!email || !email.includes("@")) {
  console.error("Usage: node scripts/bootstrap-admin.mjs you@example.com");
  process.exit(1);
}

const {FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY} = process.env;
if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY) {
  console.error(
    "Missing credentials. Copy .env.local.example to .env.local and fill it from a\n" +
      "service-account key (Firebase Console -> Project settings -> Service accounts).",
  );
  process.exit(1);
}

initializeApp({
  credential: cert({
    projectId: FIREBASE_PROJECT_ID,
    clientEmail: FIREBASE_CLIENT_EMAIL,
    privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
  }),
});

await getFirestore().collection("adminRoles").doc(email).set({
  email,
  role: "superAdmin",
  addedBy: "bootstrap-script",
  addedAt: Date.now(),
});

console.log(`✓ ${email} is now a super admin. Sign in at /login with that Google account.`);
process.exit(0);
