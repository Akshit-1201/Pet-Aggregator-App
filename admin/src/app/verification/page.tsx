import {redirect} from "next/navigation";
import {Empty, Shell} from "@/components/Shell";
import {listVerificationRequests, signDocumentUrls} from "@/lib/data";
import {getSession} from "@/lib/session";
import {can} from "@/lib/roles";
import {VerificationRowCard} from "./VerificationRowCard";

export const dynamic = "force-dynamic";

export default async function VerificationPage() {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await listVerificationRequests("pending");
  // Sign here, in the server component — the URLs are short-lived and must never
  // be derivable on the client.
  const withDocs = await Promise.all(
    rows.map(async (row) => ({row, docUrls: await signDocumentUrls(row.docPaths)})),
  );

  return (
    <Shell session={session} title="Verification queue">
      {withDocs.length === 0 ? (
        <Empty>Nothing waiting. New applications appear here as partners submit them.</Empty>
      ) : (
        <div className="space-y-4">
          {withDocs.map(({row, docUrls}) => (
            <VerificationRowCard
              key={row.uid}
              row={row}
              docUrls={docUrls}
              canReview={can(session.role, "reviewVerification")}
            />
          ))}
        </div>
      )}
    </Shell>
  );
}
