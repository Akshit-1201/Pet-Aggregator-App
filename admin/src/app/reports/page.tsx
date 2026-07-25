import {redirect} from "next/navigation";
import {Empty, Shell} from "@/components/Shell";
import {listReports} from "@/lib/data";
import {getSession} from "@/lib/session";
import {can} from "@/lib/roles";
import {ReportRowCard} from "./ReportRowCard";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await listReports("open");

  return (
    <Shell session={session} title="Open reports">
      {rows.length === 0 ? (
        <Empty>No open reports.</Empty>
      ) : (
        <div className="space-y-4">
          {rows.map((row) => (
            <ReportRowCard
              key={row.id}
              row={row}
              canAction={can(session.role, "actionReports")}
            />
          ))}
        </div>
      )}
    </Shell>
  );
}
