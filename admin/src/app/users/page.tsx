import {redirect} from "next/navigation";
import {Card, Empty, Shell} from "@/components/Shell";
import {findUser} from "@/lib/data";
import {getSession} from "@/lib/session";
import {can} from "@/lib/roles";
import {UserCard} from "./UserCard";

export const dynamic = "force-dynamic";

export default async function UsersPage({
  searchParams,
}: {
  // Next 16: searchParams is a Promise. Synchronous access was removed.
  searchParams: Promise<{q?: string}>;
}) {
  const session = await getSession();
  if (!session) redirect("/login");

  const {q = ""} = await searchParams;
  const user = q ? await findUser(q) : null;

  return (
    <Shell session={session} title="Users">
      <Card>
        <form className="flex flex-wrap gap-2">
          <input
            name="q"
            defaultValue={q}
            placeholder="Email address or uid"
            className="min-w-64 flex-1 rounded-xl border border-neutral-200 px-3 py-2 text-sm"
          />
          <button className="rounded-xl bg-[#F0871E] px-4 py-2 text-sm font-bold text-white hover:bg-[#e0770f]">
            Find
          </button>
        </form>
        <p className="mt-2 text-xs text-neutral-500">
          Exact match only — Firestore has no substring search, so a partial name
          will not find anyone.
        </p>
      </Card>

      <div className="mt-4">
        {q && !user && <Empty>No account matches “{q}”.</Empty>}
        {user && <UserCard user={user} canSuspend={can(session.role, "suspendUsers")} />}
      </div>
    </Shell>
  );
}
