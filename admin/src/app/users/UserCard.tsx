"use client";
import {useState, useTransition} from "react";
import {setUserSuspended} from "@/app/actions";
import type {UserRow} from "@/lib/data";

export function UserCard({user, canSuspend}: {user: UserRow; canSuspend: boolean}) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [pending, start] = useTransition();

  function toggle() {
    setError("");
    start(async () => {
      const result = await setUserSuspended(user.uid, !user.disabled, reason);
      if (!result.ok) setError(result.error);
    });
  }

  return (
    <div className="rounded-2xl bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="text-base font-bold">{user.name || "(no name)"}</span>
        {user.role && (
          <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-semibold text-neutral-600">
            {user.role}
          </span>
        )}
        {user.disabled && (
          <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-bold text-red-700">
            Suspended
          </span>
        )}
      </div>

      <dl className="mt-3 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
        <div>
          <dt className="inline text-neutral-500">Email: </dt>
          <dd className="inline">{user.email}</dd>
        </div>
        <div>
          <dt className="inline text-neutral-500">Area: </dt>
          <dd className="inline">{user.area || "—"}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="inline text-neutral-500">uid: </dt>
          <dd className="inline font-mono text-xs">{user.uid}</dd>
        </div>
      </dl>

      {canSuspend ? (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          {!user.disabled && (
            <input
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Reason for suspension"
              className="min-w-56 flex-1 rounded-xl border border-neutral-200 px-3 py-2 text-sm"
            />
          )}
          <button
            onClick={toggle}
            disabled={pending}
            className={`rounded-xl px-4 py-2 text-sm font-bold text-white disabled:opacity-60 ${
              user.disabled ? "bg-emerald-600 hover:bg-emerald-700" : "bg-red-600 hover:bg-red-700"
            }`}
          >
            {user.disabled ? "Reactivate" : "Suspend"}
          </button>
        </div>
      ) : (
        <p className="mt-4 text-sm text-neutral-500">
          Your role can view accounts but not suspend them.
        </p>
      )}

      <p className="mt-3 text-xs text-neutral-500">
        Suspension disables the Firebase Auth account, so they are locked out on
        their next token refresh rather than only inside the app.
      </p>

      {error && (
        <p className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
      )}
    </div>
  );
}
