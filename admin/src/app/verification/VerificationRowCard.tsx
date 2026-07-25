"use client";
import {useState, useTransition} from "react";
import {approveVerification, rejectVerification} from "@/app/actions";
import type {VerificationRow} from "@/lib/data";

const when = (ms: number) => (ms ? new Date(ms).toLocaleDateString() : "—");

export function VerificationRowCard({
  row,
  docUrls,
  canReview,
}: {
  row: VerificationRow;
  docUrls: string[];
  canReview: boolean;
}) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [pending, start] = useTransition();

  function run(fn: () => Promise<{ok: boolean; error?: string}>) {
    setError("");
    start(async () => {
      const result = await fn();
      if (!result.ok) setError(result.error ?? "Action failed.");
    });
  }

  return (
    <div className="rounded-2xl bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="text-base font-bold">{row.applicantName || "(no name)"}</span>
        <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-semibold text-neutral-600">
          {row.kind === "homestay" ? "Homestay host" : "Service pro"}
        </span>
        <span className="text-sm text-neutral-500">{row.area || "—"}</span>
        <span className="ml-auto text-sm text-neutral-400">
          Submitted {when(row.submittedAt)}
        </span>
      </div>

      <div className="mt-4 flex flex-wrap gap-3">
        {docUrls.length === 0 && (
          <p className="text-sm text-red-700">
            Documents could not be loaded. They may have been deleted from Storage.
          </p>
        )}
        {docUrls.map((url, i) => (
          // Signed URLs expire in 15 minutes, so these are intentionally not
          // cached or optimised through next/image.
          <a key={url} href={url} target="_blank" rel="noreferrer" className="block">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={url}
              alt={`Document ${i + 1}`}
              className="h-28 w-28 rounded-xl border border-black/5 object-cover"
            />
          </a>
        ))}
      </div>

      {canReview ? (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <button
            onClick={() => run(() => approveVerification(row.uid, row.kind))}
            disabled={pending}
            className="rounded-xl bg-emerald-600 px-4 py-2 text-sm font-bold text-white hover:bg-emerald-700 disabled:opacity-60"
          >
            Approve
          </button>
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Reason (shown to the applicant)"
            className="min-w-56 flex-1 rounded-xl border border-neutral-200 px-3 py-2 text-sm"
          />
          <button
            onClick={() => run(() => rejectVerification(row.uid, reason))}
            disabled={pending}
            className="rounded-xl bg-neutral-800 px-4 py-2 text-sm font-bold text-white hover:bg-black disabled:opacity-60"
          >
            Reject
          </button>
        </div>
      ) : (
        <p className="mt-4 text-sm text-neutral-500">
          Your role can view this queue but not decide on it.
        </p>
      )}

      {error && (
        <p className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
      )}
    </div>
  );
}
