import Link from "next/link";
import {redirect} from "next/navigation";
import {Card, Shell} from "@/components/Shell";
import {queueCounts} from "@/lib/data";
import {getSession} from "@/lib/session";

export const dynamic = "force-dynamic";

export default async function OverviewPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const counts = await queueCounts();

  return (
    <Shell session={session} title="Overview">
      <div className="grid gap-4 sm:grid-cols-2">
        <Link href="/verification">
          <Card>
            <div className="text-sm font-semibold text-neutral-500">Pending verification</div>
            <div className="mt-1 text-3xl font-extrabold">{counts.pendingVerifications}</div>
            <div className="mt-1 text-sm text-neutral-500">Partners waiting on a decision</div>
          </Card>
        </Link>
        <Link href="/reports">
          <Card>
            <div className="text-sm font-semibold text-neutral-500">Open reports</div>
            <div className="mt-1 text-3xl font-extrabold">{counts.openReports}</div>
            <div className="mt-1 text-sm text-neutral-500">Reported content and people</div>
          </Card>
        </Link>
      </div>
    </Shell>
  );
}
