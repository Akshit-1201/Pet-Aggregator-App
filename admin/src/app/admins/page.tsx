import {redirect} from "next/navigation";
import {Card, Shell} from "@/components/Shell";
import {adminDb} from "@/lib/firebase-admin";
import {getSession} from "@/lib/session";
import {can, ROLE_LABEL, isRole} from "@/lib/roles";
import {AdminsEditor} from "./AdminsEditor";

export const dynamic = "force-dynamic";

export default async function AdminsPage() {
  const session = await getSession();
  if (!session) redirect("/login");
  // Server-side gate, not just a hidden nav link.
  if (!can(session.role, "manageAdmins")) {
    return (
      <Shell session={session} title="Admins">
        <Card>
          <p className="text-sm text-neutral-600">
            Only a super admin can manage admin roles.
          </p>
        </Card>
      </Shell>
    );
  }

  const snap = await adminDb().collection("adminRoles").get();
  const admins = snap.docs
    .map((d) => ({email: d.id, role: isRole(d.data().role) ? d.data().role : "support"}))
    .sort((a, b) => a.email.localeCompare(b.email));

  return (
    <Shell session={session} title="Admins">
      <AdminsEditor admins={admins} currentEmail={session.email} roleLabels={ROLE_LABEL} />
    </Shell>
  );
}
