import Link from "next/link";
import {redirect} from "next/navigation";
import {Card, Empty, Shell} from "@/components/Shell";
import {listPayouts} from "@/lib/data";
import {getSession} from "@/lib/session";

export const dynamic = "force-dynamic";

const money = (n: number) => `₹${n.toLocaleString("en-IN")}`;
const day = (ms: number) => (ms ? new Date(ms).toLocaleDateString() : "—");

const STATUS_STYLE: Record<string, string> = {
  owed: "bg-amber-100 text-amber-800",
  held: "bg-blue-100 text-blue-800",
  released: "bg-emerald-100 text-emerald-800",
  reversed: "bg-neutral-200 text-neutral-600",
  failed: "bg-red-100 text-red-700",
};

export default async function PayoutsPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await listPayouts();
  const totals = rows.reduce(
    (acc, r) => {
      if (r.status === "owed" || r.status === "held") acc.pending += r.amount;
      if (r.status === "released") acc.paid += r.amount;
      return acc;
    },
    {pending: 0, paid: 0},
  );
  const blocked = rows.filter((r) => r.status === "owed" && !r.hasAccount).length;

  return (
    <Shell session={session} title="Payouts">
      <div className="mb-4 grid gap-4 sm:grid-cols-3">
        <Card>
          <div className="text-sm font-semibold text-neutral-500">Owed &amp; in flight</div>
          <div className="mt-1 text-2xl font-extrabold">{money(totals.pending)}</div>
        </Card>
        <Card>
          <div className="text-sm font-semibold text-neutral-500">Paid out</div>
          <div className="mt-1 text-2xl font-extrabold">{money(totals.paid)}</div>
        </Card>
        <Card>
          <div className="text-sm font-semibold text-neutral-500">Waiting on bank details</div>
          <div className="mt-1 text-2xl font-extrabold">{blocked}</div>
          <div className="mt-1 text-xs text-neutral-500">
            Partners earning but not yet payable
          </div>
        </Card>
      </div>

      {rows.length === 0 ? (
        <Empty>
          No payouts yet. One is recorded each time a customer pays, and released once
          the booking completes.
        </Empty>
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[52rem] text-left text-sm">
              <thead className="text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="pb-2 pr-4 font-semibold">Status</th>
                  <th className="pb-2 pr-4 font-semibold">Amount</th>
                  <th className="pb-2 pr-4 font-semibold">Partner</th>
                  <th className="pb-2 pr-4 font-semibold">Booking</th>
                  <th className="pb-2 pr-4 font-semibold">Releasable</th>
                  <th className="pb-2 font-semibold">Note</th>
                </tr>
              </thead>
              <tbody className="align-top">
                {rows.map((r) => (
                  <tr key={r.id} className="border-t border-black/5">
                    <td className="py-2 pr-4">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-bold ${
                          STATUS_STYLE[r.status] ?? "bg-neutral-100 text-neutral-600"
                        }`}
                      >
                        {r.status}
                      </span>
                    </td>
                    <td className="py-2 pr-4 font-semibold">{money(r.amount)}</td>
                    <td className="py-2 pr-4">
                      <Link className="font-mono text-xs underline" href={`/users?q=${r.partnerId}`}>
                        {r.partnerId}
                      </Link>
                      {!r.hasAccount && (
                        <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-800">
                          no bank details
                        </span>
                      )}
                    </td>
                    <td className="py-2 pr-4 font-mono text-xs">
                      {r.kind}/{r.bookingId}
                    </td>
                    <td className="py-2 pr-4 whitespace-nowrap text-neutral-500">
                      {day(r.dueAt)}
                    </td>
                    <td className="py-2 text-neutral-600">{r.error || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      <p className="mt-4 text-xs text-neutral-500">
        Transfers are created on hold when a customer pays and released the day after the
        booking completes, so a refund can reverse them cleanly. A partner with no bank
        details keeps accruing as <strong>owed</strong> until they add one.
      </p>
    </Shell>
  );
}
