"use client";
import {useState, useTransition} from "react";
import Link from "next/link";
import {dismissReport, removeReportedContent} from "@/app/actions";
import type {ReportRow} from "@/lib/data";

const REASON_LABEL: Record<string, string> = {
  spam: "Spam or scam",
  harassment: "Harassment or bullying",
  hate: "Hate speech",
  sexual: "Sexual or explicit content",
  animalWelfare: "Animal welfare concern",
  impersonation: "Impersonation or fake listing",
  other: "Something else",
};

/** Only posts and comments have deletable content; a reported person or listing
 *  is handled by suspending them instead. */
const DELETABLE = new Set(["post", "comment"]);

export function ReportRowCard({row, canAction}: {row: ReportRow; canAction: boolean}) {
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
        <span className="text-base font-bold">
          {REASON_LABEL[row.reason] ?? row.reason}
        </span>
        <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-semibold text-neutral-600">
          {row.targetType}
        </span>
        <span className="ml-auto text-sm text-neutral-400">
          {row.createdAt ? new Date(row.createdAt).toLocaleString() : "—"}
        </span>
      </div>

      <dl className="mt-3 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
        <div>
          <dt className="inline text-neutral-500">Target: </dt>
          <dd className="inline font-mono text-xs">{row.targetId}</dd>
        </div>
        {row.contextId && (
          <div>
            <dt className="inline text-neutral-500">In post: </dt>
            <dd className="inline font-mono text-xs">{row.contextId}</dd>
          </div>
        )}
        {row.targetOwnerId && (
          <div>
            <dt className="inline text-neutral-500">Author: </dt>
            <dd className="inline font-mono text-xs">
              <Link className="underline" href={`/users?q=${row.targetOwnerId}`}>
                {row.targetOwnerId}
              </Link>
            </dd>
          </div>
        )}
        <div>
          <dt className="inline text-neutral-500">Reported by: </dt>
          <dd className="inline font-mono text-xs">{row.reporterId}</dd>
        </div>
      </dl>

      {row.note && <p className="mt-2 text-sm text-neutral-600">{row.note}</p>}

      {canAction ? (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            onClick={() => run(() => dismissReport(row.id))}
            disabled={pending}
            className="rounded-xl bg-neutral-100 px-4 py-2 text-sm font-bold text-neutral-700 hover:bg-neutral-200 disabled:opacity-60"
          >
            Dismiss
          </button>
          {DELETABLE.has(row.targetType) && (
            <button
              onClick={() =>
                run(() =>
                  removeReportedContent(row.id, row.targetType, row.targetId, row.contextId),
                )
              }
              disabled={pending}
              className="rounded-xl bg-red-600 px-4 py-2 text-sm font-bold text-white hover:bg-red-700 disabled:opacity-60"
            >
              Remove content
            </button>
          )}
          {row.targetOwnerId && (
            <Link
              href={`/users?q=${row.targetOwnerId}`}
              className="rounded-xl bg-neutral-800 px-4 py-2 text-sm font-bold text-white hover:bg-black"
            >
              Review the person
            </Link>
          )}
        </div>
      ) : (
        <p className="mt-4 text-sm text-neutral-500">
          Your role can view reports but not action them.
        </p>
      )}

      {error && (
        <p className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
      )}
    </div>
  );
}
