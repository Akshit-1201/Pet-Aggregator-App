import "server-only";
import {cookies} from "next/headers";
import {adminAuth, adminDb} from "./firebase-admin";
import {isRole, can, type Capability, type Role} from "./roles";
import {SESSION_COOKIE} from "./session-cookie";

export {SESSION_COOKIE};
const SESSION_MAX_AGE_MS = 8 * 60 * 60 * 1000; // 8h — a staff shift, then re-auth

export type AdminSession = {uid: string; email: string; role: Role};

/**
 * The authorisation decision, in one place.
 *
 * An email is an admin **only** if it has a row in `adminRoles`. That lookup
 * happens on every sign-in rather than trusting the claim alone, so revoking
 * access is a single Firestore delete rather than a claim-propagation problem.
 */
export async function lookupAdminRole(email: string): Promise<Role | null> {
  const snap = await adminDb().collection("adminRoles").doc(email.toLowerCase()).get();
  if (!snap.exists) return null;
  const role = snap.data()?.role;
  return isRole(role) ? role : null;
}

/** Exchanges a verified Google ID token for a session cookie. */
export async function createSession(idToken: string): Promise<AdminSession> {
  const decoded = await adminAuth().verifyIdToken(idToken, true);
  const email = decoded.email?.toLowerCase();
  if (!email) throw new Error("That Google account has no email address.");

  const role = await lookupAdminRole(email);
  if (!role) {
    // Deliberately says nothing about whether the account exists — an
    // unauthorised person learns only that they are not staff.
    throw new Error("That account is not authorised for the Pawgo admin panel.");
  }

  // Claims mirror the allowlist so other Firebase surfaces can trust them too.
  await adminAuth().setCustomUserClaims(decoded.uid, {admin: true, role});

  const cookie = await adminAuth().createSessionCookie(idToken, {
    expiresIn: SESSION_MAX_AGE_MS,
  });
  (await cookies()).set(SESSION_COOKIE, cookie, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    maxAge: SESSION_MAX_AGE_MS / 1000,
    path: "/",
  });
  return {uid: decoded.uid, email, role};
}

export async function destroySession() {
  (await cookies()).delete(SESSION_COOKIE);
}

/** The current admin, or null. Re-reads the allowlist so a revoked admin is
 *  locked out on their next request, not when their cookie eventually expires. */
export async function getSession(): Promise<AdminSession | null> {
  const cookie = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!cookie) return null;
  try {
    const decoded = await adminAuth().verifySessionCookie(cookie, true);
    const email = decoded.email?.toLowerCase();
    if (!email) return null;
    const role = await lookupAdminRole(email);
    if (!role) return null;
    return {uid: decoded.uid, email, role};
  } catch {
    return null; // expired, revoked, or tampered
  }
}

/**
 * Gate for every server action. Throws rather than returning a flag so a
 * forgotten check cannot silently fall through to the mutation below it.
 */
export async function requireCapability(capability: Capability): Promise<AdminSession> {
  const session = await getSession();
  if (!session) throw new Error("Not signed in.");
  if (!can(session.role, capability)) {
    throw new Error(`Your role (${session.role}) cannot perform this action.`);
  }
  return session;
}
