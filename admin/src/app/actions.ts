"use server";
import {revalidatePath} from "next/cache";
import {adminAuth, adminDb} from "@/lib/firebase-admin";
import {requireCapability} from "@/lib/session";
import {writeAudit} from "@/lib/audit";
import {isRole} from "@/lib/roles";

/**
 * Every mutation the panel can perform.
 *
 * A server action is a POST endpoint reachable by anyone who can craft the
 * request — the Next docs are explicit that it is an untrusted entry point. So
 * each one starts with `requireCapability`, which throws. Hiding a button in the
 * UI is not access control.
 *
 * Each also writes an audit entry in the same path as the mutation.
 */

export type ActionResult = {ok: true} | {ok: false; error: string};

async function guarded(
  capability: Parameters<typeof requireCapability>[0],
  run: (session: Awaited<ReturnType<typeof requireCapability>>) => Promise<void>,
): Promise<ActionResult> {
  try {
    const session = await requireCapability(capability);
    await run(session);
    return {ok: true};
  } catch (e) {
    return {ok: false, error: e instanceof Error ? e.message : "Action failed."};
  }
}

export async function approveVerification(uid: string, kind: string): Promise<ActionResult> {
  return guarded("reviewVerification", async (session) => {
    const collection = kind === "homestay" ? "homestays" : "pros";
    const db = adminDb();
    const listing = db.collection(collection).doc(uid);
    if (!(await listing.get()).exists) {
      throw new Error(`No ${collection} listing exists for this user yet.`);
    }
    // `verified` is rejected for every client write, so this is the only path
    // that can grant it.
    await listing.update({verified: true});
    await db.collection("verificationRequests").doc(uid).update({
      status: "approved",
      reviewedBy: session.email,
      reviewedAt: Date.now(),
      reason: "",
    });
    await writeAudit(session, "verification.approve", {type: kind, id: uid});
  }).then((r) => {
    revalidatePath("/verification");
    revalidatePath("/");
    return r;
  });
}

export async function rejectVerification(uid: string, reason: string): Promise<ActionResult> {
  return guarded("reviewVerification", async (session) => {
    if (!reason.trim()) throw new Error("Give a reason — the applicant sees it.");
    await adminDb().collection("verificationRequests").doc(uid).update({
      status: "rejected",
      reviewedBy: session.email,
      reviewedAt: Date.now(),
      reason: reason.trim(),
    });
    await writeAudit(session, "verification.reject", {type: "verification", id: uid}, reason.trim());
  }).then((r) => {
    revalidatePath("/verification");
    revalidatePath("/");
    return r;
  });
}

export async function dismissReport(id: string): Promise<ActionResult> {
  return guarded("actionReports", async (session) => {
    await adminDb().collection("reports").doc(id).update({
      status: "dismissed",
      resolvedBy: session.email,
      resolvedAt: Date.now(),
    });
    await writeAudit(session, "report.dismiss", {type: "report", id});
  }).then((r) => {
    revalidatePath("/reports");
    revalidatePath("/");
    return r;
  });
}

/** Removes the reported content itself. Posts and comments are deleted; a
 *  reported person or listing has no "content" to remove, so those resolve to a
 *  suspension decision instead and are refused here rather than silently no-op. */
export async function removeReportedContent(
  id: string,
  targetType: string,
  targetId: string,
  contextId: string,
): Promise<ActionResult> {
  return guarded("actionReports", async (session) => {
    const db = adminDb();
    if (targetType === "post") {
      await db.collection("posts").doc(targetId).delete();
    } else if (targetType === "comment") {
      if (!contextId) throw new Error("This comment report has no post id recorded.");
      await db.collection("posts").doc(contextId).collection("comments").doc(targetId).delete();
    } else {
      throw new Error(
        `A ${targetType} report has no content to delete — suspend the person instead.`,
      );
    }
    await db.collection("reports").doc(id).update({
      status: "actioned",
      resolvedBy: session.email,
      resolvedAt: Date.now(),
    });
    await writeAudit(session, "report.removeContent", {type: targetType, id: targetId});
  }).then((r) => {
    revalidatePath("/reports");
    revalidatePath("/");
    return r;
  });
}

/**
 * Suspension uses Firebase Auth `disabled`, not a Firestore flag: it invalidates
 * tokens at the source, so a suspended person is locked out on their next token
 * refresh rather than only in clients that remember to honour a flag.
 */
export async function setUserSuspended(
  uid: string,
  suspended: boolean,
  reason: string,
): Promise<ActionResult> {
  return guarded("suspendUsers", async (session) => {
    if (suspended && !reason.trim()) throw new Error("Give a reason for the suspension.");
    await adminAuth().updateUser(uid, {disabled: suspended});
    await writeAudit(
      session,
      suspended ? "user.suspend" : "user.reactivate",
      {type: "user", id: uid},
      reason.trim(),
    );
  }).then((r) => {
    revalidatePath("/users");
    return r;
  });
}

export async function setAdminRole(email: string, role: string): Promise<ActionResult> {
  return guarded("manageAdmins", async (session) => {
    const target = email.trim().toLowerCase();
    if (!target.includes("@")) throw new Error("Enter a full email address.");
    if (!isRole(role)) throw new Error("Unknown role.");
    // Losing the last super-admin would lock everyone out of role management
    // with no way back except editing Firestore by hand.
    if (target === session.email && role !== "superAdmin") {
      throw new Error("You cannot demote yourself.");
    }
    await adminDb().collection("adminRoles").doc(target).set({
      email: target,
      role,
      addedBy: session.email,
      addedAt: Date.now(),
    });
    await writeAudit(session, "admin.setRole", {type: "admin", id: target}, role);
  }).then((r) => {
    revalidatePath("/admins");
    return r;
  });
}

export async function removeAdmin(email: string): Promise<ActionResult> {
  return guarded("manageAdmins", async (session) => {
    const target = email.trim().toLowerCase();
    if (target === session.email) throw new Error("You cannot remove yourself.");
    await adminDb().collection("adminRoles").doc(target).delete();
    await writeAudit(session, "admin.setRole", {type: "admin", id: target}, "removed");
  }).then((r) => {
    revalidatePath("/admins");
    return r;
  });
}
