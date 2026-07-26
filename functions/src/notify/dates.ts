/** Formats a date-only `YYYY-MM-DD` booking field as the human label Pawgo
 *  shows everywhere else ("Mon, 3 Aug"), so a receipt doesn't stand out from
 *  the rest of the notification catalogue by showing a raw ISO string.
 *
 *  A leaf module (no other `notify` imports) so both `triggers.ts` and
 *  `index.ts` can import it without `index.ts` having to reach into
 *  `triggers.ts` for a formatting helper. */
export const fmtDay = (iso: string): string => {
  const d = new Date(`${String(iso).slice(0, 10)}T00:00:00+05:30`);
  return Number.isFinite(d.getTime()) ?
    d.toLocaleDateString("en-IN", {weekday: "short", day: "numeric", month: "short",
      timeZone: "Asia/Kolkata"}) : String(iso);
};
