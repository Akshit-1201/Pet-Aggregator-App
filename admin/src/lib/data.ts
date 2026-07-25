import "server-only";
import {adminAuth, adminDb, adminStorage} from "./firebase-admin";

export type VerificationRow = {
  uid: string;
  kind: "pro" | "homestay";
  status: "pending" | "approved" | "rejected";
  applicantName: string;
  area: string;
  docPaths: string[];
  submittedAt: number;
  reviewedBy: string;
  reason: string;
};

export type ReportRow = {
  id: string;
  reporterId: string;
  targetType: string;
  targetId: string;
  targetOwnerId: string;
  contextId: string;
  reason: string;
  note: string;
  status: string;
  createdAt: number;
};

export type AuditRow = {
  id: string;
  actorEmail: string;
  actorRole: string;
  action: string;
  targetType: string;
  targetId: string;
  reason: string;
  at: number;
};

const num = (v: unknown) => (typeof v === "number" ? v : 0);
const str = (v: unknown) => (typeof v === "string" ? v : "");

export async function listVerificationRequests(
  status: VerificationRow["status"] = "pending",
): Promise<VerificationRow[]> {
  // No orderBy alongside the where: that needs a composite index, and these
  // queues are small enough to sort in memory.
  const snap = await adminDb()
    .collection("verificationRequests")
    .where("status", "==", status)
    .limit(200)
    .get();
  return snap.docs
    .map((d) => {
      const x = d.data();
      return {
        uid: d.id,
        kind: x.kind === "homestay" ? "homestay" : "pro",
        status: (x.status ?? "pending") as VerificationRow["status"],
        applicantName: str(x.applicantName),
        area: str(x.area),
        docPaths: Array.isArray(x.docPaths) ? x.docPaths.filter((p) => typeof p === "string") : [],
        submittedAt: num(x.submittedAt),
        reviewedBy: str(x.reviewedBy),
        reason: str(x.reason),
      } satisfies VerificationRow;
    })
    .sort((a, b) => a.submittedAt - b.submittedAt); // oldest first — a queue
}

export async function listReports(status = "open"): Promise<ReportRow[]> {
  const snap = await adminDb()
    .collection("reports")
    .where("status", "==", status)
    .limit(200)
    .get();
  return snap.docs
    .map((d) => {
      const x = d.data();
      return {
        id: d.id,
        reporterId: str(x.reporterId),
        targetType: str(x.targetType),
        targetId: str(x.targetId),
        targetOwnerId: str(x.targetOwnerId),
        contextId: str(x.contextId),
        reason: str(x.reason),
        note: str(x.note),
        status: str(x.status),
        createdAt: num(x.createdAt),
      } satisfies ReportRow;
    })
    .sort((a, b) => a.createdAt - b.createdAt);
}

export async function listAudit(limit = 100): Promise<AuditRow[]> {
  const snap = await adminDb().collection("auditLogs").orderBy("at", "desc").limit(limit).get();
  return snap.docs.map((d) => {
    const x = d.data();
    return {
      id: d.id,
      actorEmail: str(x.actorEmail),
      actorRole: str(x.actorRole),
      action: str(x.action),
      targetType: str(x.targetType),
      targetId: str(x.targetId),
      reason: str(x.reason),
      at: num(x.at),
    } satisfies AuditRow;
  });
}

/**
 * Short-lived read URLs for KYC documents.
 *
 * The objects are unreadable by any client (`storage.rules` denies read on
 * `verification/`), which is the whole point — an ID document must not be a
 * public link like the pet photos are. The Admin SDK signs a URL that expires
 * in 15 minutes so a reviewer can look without the document becoming shareable.
 */
export async function signDocumentUrls(paths: string[]): Promise<string[]> {
  const bucket = adminStorage().bucket();
  const expires = Date.now() + 15 * 60 * 1000;
  const urls = await Promise.all(
    paths.map(async (path) => {
      try {
        const [url] = await bucket.file(path).getSignedUrl({action: "read", expires});
        return url;
      } catch {
        return ""; // a missing object must not take down the whole queue
      }
    }),
  );
  return urls.filter(Boolean);
}

export type UserRow = {
  uid: string;
  name: string;
  email: string;
  area: string;
  role: string;
  disabled: boolean;
};

/** Looks a user up by email or uid. Firestore has no substring search, so this
 *  is exact-match by design rather than a half-working "search". */
export async function findUser(query: string): Promise<UserRow | null> {
  const q = query.trim();
  if (!q) return null;

  let uid = "";
  let disabled = false;
  try {
    const record = q.includes("@")
      ? await adminAuth().getUserByEmail(q)
      : await adminAuth().getUser(q);
    uid = record.uid;
    disabled = record.disabled;
  } catch {
    return null;
  }

  const snap = await adminDb().collection("users").doc(uid).get();
  const x = snap.data() ?? {};
  return {
    uid,
    name: str(x.name),
    email: str(x.email) || q,
    area: str(x.area),
    role: str(x.role),
    disabled,
  };
}

export type PayoutLedgerRow = {
  id: string;
  kind: string;
  bookingId: string;
  partnerId: string;
  amount: number;
  status: string;
  transferId: string;
  dueAt: number;
  createdAt: number;
  error: string;
  hasAccount: boolean;
};

/**
 * The payout ledger. `owed` first because that is the row a human has to care
 * about — either the partner has not given bank details, or a transfer is
 * failing. Released rows are just history.
 */
export async function listPayouts(): Promise<PayoutLedgerRow[]> {
  const db = adminDb();
  const snap = await db.collection("payouts").orderBy("createdAt", "desc").limit(200).get();

  // One read per distinct partner, not per row.
  const partnerIds = [...new Set(snap.docs.map((d) => str(d.data().partnerId)).filter(Boolean))];
  const accounts = await Promise.all(
    partnerIds.map((id) => db.collection("payoutAccounts").doc(id).get()),
  );
  const withAccount = new Set(
    accounts.filter((a) => a.exists && a.data()?.razorpayAccountId).map((a) => a.id),
  );

  const ORDER: Record<string, number> = {owed: 0, held: 1, failed: 2, released: 3, reversed: 4};
  return snap.docs
    .map((d) => {
      const x = d.data();
      return {
        id: d.id,
        kind: str(x.kind),
        bookingId: str(x.bookingId),
        partnerId: str(x.partnerId),
        amount: num(x.amount),
        status: str(x.status),
        transferId: str(x.transferId),
        dueAt: num(x.dueAt),
        createdAt: num(x.createdAt),
        error: str(x.error),
        hasAccount: withAccount.has(str(x.partnerId)),
      } satisfies PayoutLedgerRow;
    })
    .sort((a, b) => (ORDER[a.status] ?? 9) - (ORDER[b.status] ?? 9) || b.createdAt - a.createdAt);
}

export async function queueCounts() {
  const [verifications, reports] = await Promise.all([
    adminDb().collection("verificationRequests").where("status", "==", "pending").count().get(),
    adminDb().collection("reports").where("status", "==", "open").count().get(),
  ]);
  return {
    pendingVerifications: verifications.data().count,
    openReports: reports.data().count,
  };
}
