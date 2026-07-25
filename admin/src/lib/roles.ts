/**
 * RBAC, shared by server actions and the nav.
 *
 * Roles are checked **server-side in every action**. The UI hides what a role
 * cannot do, but hiding a button is not access control — a `support` admin who
 * crafts the request by hand must still be refused.
 */
export const ROLES = ["superAdmin", "moderator", "support"] as const;
export type Role = (typeof ROLES)[number];

export function isRole(value: unknown): value is Role {
  return typeof value === "string" && (ROLES as readonly string[]).includes(value);
}

/** Capabilities, mirroring the matrix in the Phase 12 spec. */
export const CAN = {
  viewQueues: ["superAdmin", "moderator", "support"],
  reviewVerification: ["superAdmin", "moderator"],
  actionReports: ["superAdmin", "moderator"],
  suspendUsers: ["superAdmin", "moderator"],
  manageAdmins: ["superAdmin"],
} as const satisfies Record<string, readonly Role[]>;

export type Capability = keyof typeof CAN;

export const can = (role: Role, capability: Capability): boolean =>
  (CAN[capability] as readonly Role[]).includes(role);

export const ROLE_LABEL: Record<Role, string> = {
  superAdmin: "Super admin",
  moderator: "Moderator",
  support: "Support",
};
