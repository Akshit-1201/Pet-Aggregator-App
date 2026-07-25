import {cert, getApps, initializeApp, type App} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

/**
 * Admin SDK, server-only.
 *
 * Every privileged read and write in this app goes through here. The Admin SDK
 * bypasses security rules entirely, which is exactly why nothing in `src/app`
 * may import it from a client component — it is the reason `firestore.rules`
 * can deny clients access to `adminRoles`, `auditLogs` and KYC documents while
 * the panel still reads them.
 *
 * Credentials come from env (see .env.local.example). Next.js hot-reloads
 * modules, so guard against re-initialising on every reload.
 */
function initAdmin(): App {
  const existing = getApps();
  if (existing.length > 0) return existing[0];

  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  // Private keys carry literal newlines that env files can't hold, so they are
  // stored with \n escapes and unescaped here.
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, "\n");

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      "Firebase Admin credentials are missing. Copy admin/.env.local.example " +
        "to admin/.env.local and fill it from a service-account key " +
        "(Firebase Console -> Project settings -> Service accounts -> Generate new private key).",
    );
  }

  return initializeApp({
    credential: cert({projectId, clientEmail, privateKey}),
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
  });
}

export const adminAuth = () => getAuth(initAdmin());
export const adminDb = () => getFirestore(initAdmin());
export const adminStorage = () => getStorage(initAdmin());
