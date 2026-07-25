"use client";
import {useState, useTransition} from "react";
import {removeAdmin, setAdminRole} from "@/app/actions";
import {ROLES, type Role} from "@/lib/roles";

export function AdminsEditor({
  admins,
  currentEmail,
  roleLabels,
}: {
  admins: {email: string; role: Role}[];
  currentEmail: string;
  roleLabels: Record<Role, string>;
}) {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("moderator");
  const [error, setError] = useState("");
  const [pending, start] = useTransition();

  function run(fn: () => Promise<{ok: boolean; error?: string}>) {
    setError("");
    start(async () => {
      const result = await fn();
      if (!result.ok) setError(result.error ?? "Action failed.");
      else setEmail("");
    });
  }

  return (
    <div className="space-y-4">
      <div className="rounded-2xl bg-white p-5 shadow-sm">
        <h2 className="text-sm font-bold">Add or change an admin</h2>
        <p className="mt-1 text-xs text-neutral-500">
          The email must match the Google account they sign in with. Access is
          granted by this list — removing a row locks them out on their next request.
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="person@example.com"
            className="min-w-64 flex-1 rounded-xl border border-neutral-200 px-3 py-2 text-sm"
          />
          <select
            value={role}
            onChange={(e) => setRole(e.target.value as Role)}
            className="rounded-xl border border-neutral-200 px-3 py-2 text-sm"
          >
            {ROLES.map((r) => (
              <option key={r} value={r}>
                {roleLabels[r]}
              </option>
            ))}
          </select>
          <button
            onClick={() => run(() => setAdminRole(email, role))}
            disabled={pending}
            className="rounded-xl bg-[#F0871E] px-4 py-2 text-sm font-bold text-white hover:bg-[#e0770f] disabled:opacity-60"
          >
            Save
          </button>
        </div>
        {error && (
          <p className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
        )}
      </div>

      <div className="rounded-2xl bg-white p-5 shadow-sm">
        <h2 className="text-sm font-bold">Current admins</h2>
        <ul className="mt-3 divide-y divide-black/5">
          {admins.map((a) => (
            <li key={a.email} className="flex flex-wrap items-center gap-3 py-2 text-sm">
              <span>{a.email}</span>
              <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-semibold text-neutral-600">
                {roleLabels[a.role]}
              </span>
              {a.email === currentEmail ? (
                <span className="ml-auto text-xs text-neutral-400">that&apos;s you</span>
              ) : (
                <button
                  onClick={() => run(() => removeAdmin(a.email))}
                  disabled={pending}
                  className="ml-auto text-xs font-bold text-red-600 hover:underline disabled:opacity-60"
                >
                  Remove
                </button>
              )}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
