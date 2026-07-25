import {redirect} from "next/navigation";
import {Card, Empty, Shell} from "@/components/Shell";
import {listAudit} from "@/lib/data";
import {getSession} from "@/lib/session";

export const dynamic = "force-dynamic";

export default async function AuditPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await listAudit();

  return (
    <Shell session={session} title="Audit log">
      {rows.length === 0 ? (
        <Empty>Nothing logged yet. Every admin action appears here.</Empty>
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[46rem] text-left text-sm">
              <thead className="text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="pb-2 pr-4 font-semibold">When</th>
                  <th className="pb-2 pr-4 font-semibold">Who</th>
                  <th className="pb-2 pr-4 font-semibold">Action</th>
                  <th className="pb-2 pr-4 font-semibold">Target</th>
                  <th className="pb-2 font-semibold">Reason</th>
                </tr>
              </thead>
              <tbody className="align-top">
                {rows.map((row) => (
                  <tr key={row.id} className="border-t border-black/5">
                    <td className="py-2 pr-4 whitespace-nowrap text-neutral-500">
                      {row.at ? new Date(row.at).toLocaleString() : "—"}
                    </td>
                    <td className="py-2 pr-4">
                      {row.actorEmail}
                      <span className="ml-1 text-xs text-neutral-400">({row.actorRole})</span>
                    </td>
                    <td className="py-2 pr-4 font-medium">{row.action}</td>
                    <td className="py-2 pr-4 font-mono text-xs">
                      {row.targetType}/{row.targetId}
                    </td>
                    <td className="py-2 text-neutral-600">{row.reason || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </Shell>
  );
}
