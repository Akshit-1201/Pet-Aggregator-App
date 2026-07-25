import Link from "next/link";
import {signOut} from "@/app/login/actions";
import {ROLE_LABEL, can} from "@/lib/roles";
import type {AdminSession} from "@/lib/session";

const NAV = [
  {href: "/", label: "Overview"},
  {href: "/verification", label: "Verification"},
  {href: "/reports", label: "Reports"},
  {href: "/users", label: "Users"},
  {href: "/payouts", label: "Payouts"},
  {href: "/audit", label: "Audit log"},
] as const;

export function Shell({
  session,
  title,
  children,
}: {
  session: AdminSession;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen">
      <header className="border-b border-black/5 bg-white">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-3 px-6 py-4">
          <span className="text-lg font-extrabold text-[#F0871E]">Pawgo</span>
          <nav className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
            {NAV.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="font-medium text-neutral-600 transition hover:text-neutral-900"
              >
                {item.label}
              </Link>
            ))}
            {can(session.role, "manageAdmins") && (
              <Link
                href="/admins"
                className="font-medium text-neutral-600 transition hover:text-neutral-900"
              >
                Admins
              </Link>
            )}
          </nav>
          <div className="ml-auto flex items-center gap-3 text-sm">
            <span className="text-neutral-500">
              {session.email}
              <span className="ml-2 rounded-full bg-[#FDEEDC] px-2 py-0.5 text-xs font-bold text-[#B4560A]">
                {ROLE_LABEL[session.role]}
              </span>
            </span>
            <form action={signOut}>
              <button className="font-semibold text-neutral-500 hover:text-neutral-900">
                Sign out
              </button>
            </form>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-6 py-8">
        <h1 className="mb-6 text-2xl font-extrabold">{title}</h1>
        {children}
      </main>
    </div>
  );
}

export function Card({children}: {children: React.ReactNode}) {
  return <div className="rounded-2xl bg-white p-5 shadow-sm">{children}</div>;
}

export function Empty({children}: {children: React.ReactNode}) {
  return (
    <Card>
      <p className="text-sm text-neutral-500">{children}</p>
    </Card>
  );
}
