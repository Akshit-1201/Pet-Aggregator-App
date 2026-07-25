import "server-only";
import {adminDb} from "./firebase-admin";
import type {AdminSession} from "./session";

export type AuditAction =
  | "verification.approve"
  | "verification.reject"
  | "report.dismiss"
  | "report.removeContent"
  | "user.suspend"
  | "user.reactivate"
  | "admin.setRole";

/**
 * Appends an immutable audit entry.
 *
 * Called in the same code path as the mutation it describes, so an action that
 * cannot be logged does not happen. `auditLogs` is denied to clients in
 * `firestore.rules` — an audit log a client can edit is not an audit log.
 */
export async function writeAudit(
  actor: AdminSession,
  action: AuditAction,
  target: {type: string; id: string},
  reason = "",
) {
  await adminDb().collection("auditLogs").add({
    actorEmail: actor.email,
    actorRole: actor.role,
    action,
    targetType: target.type,
    targetId: target.id,
    reason,
    at: Date.now(),
  });
}
