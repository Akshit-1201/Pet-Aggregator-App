import type {EmailBody, EmailRow} from "./email";

export type PushCategory =
  | "messages" | "bookings" | "woofs" | "community" | "reminders" | "money" | "account";

/** Field names on users/{uid}. Absent means ON — accounts predating a flag
 *  must not silently go quiet. */
export const PREF_FIELD: Record<PushCategory, string> = {
  messages: "notifyMessages",
  bookings: "notifyBookings",
  woofs: "notifyWoofs",
  community: "notifyCommunity",
  reminders: "notifyReminders",
  money: "notifyMoney",     // never read: money is essential
  account: "notifyAccount", // never read: account is essential
};

/** Categories whose push ignores preferences. Failing to tell someone their
 *  refund landed or their ID was rejected is a support incident, not a
 *  preference. */
export const ESSENTIAL: ReadonlySet<PushCategory> = new Set<PushCategory>(["money", "account"]);

export type Channel = "push" | "email";
export type P = Record<string, unknown>;

/** Declared explicitly rather than inferred from CATALOG. `as const satisfies`
 *  would narrow `channels` to a readonly tuple of literals, and then
 *  `channels.includes("email")` fails to typecheck on a `["push"]` entry — and
 *  `spec.email` would not exist on the union at all. */
export type ScenarioId =
  | "MSG1"
  | "BOOK1" | "BOOK2" | "BOOK3" | "BOOK4" | "BOOK5"
  | "BOOK6" | "BOOK7" | "BOOK8" | "BOOK9" | "BOOK10"
  | "WOOF1" | "COMM1"
  | "PAY1" | "PAY2" | "PAY3" | "PAY4" | "PAY5"
  | "ACC1" | "ACC2"
  | "REM1" | "REM2" | "REM3" | "REM4" | "REM5";

export type Scenario = {
  category: PushCategory;
  essential: boolean;
  /** Overwrite the existing record instead of adding one. Push still fires per
   *  event; the feed keeps a single row. Never combined with email. */
  collapse: boolean;
  route: string;
  channels: Channel[];
  render: (p: P) => {title: string; body: string};
  email?: (p: P) => {subject: string; body: EmailBody};
};

const s = (p: P, k: string, fallback = "") => {
  const v = p[k];
  return v === undefined || v === null || v === "" ? fallback : String(v);
};
const n = (p: P, k: string) => Number(p[k] ?? 0);
const inr = (v: number) => `₹${Number(v || 0).toLocaleString("en-IN")}`;

/** What was booked, in words, for whichever pillar this is. Keeps every
 *  money template pillar-correct — the bug that made refund emails say
 *  "Your stay at your Dog walking with Rahul was cancelled". */
const subject = (p: P) => s(p, "kind") === "service" ?
  `${s(p, "serviceType", "your booking")} with ${s(p, "proName", "your pro")}` :
  `your stay at ${s(p, "homeName", "the home")}`;

const receiptLines = (p: P): EmailRow[] => s(p, "kind") === "service" ?
  [{label: `${s(p, "serviceType", "Service")} with ${s(p, "proName", "your pro")}`, amount: n(p, "rate")},
    {label: "Pawgo service fee", amount: n(p, "fee")}] :
  [{label: `${n(p, "nights")} nights at ${s(p, "homeName", "the home")}`, amount: n(p, "subtotal")},
    {label: "Pawgo service fee", amount: n(p, "fee")}];

const BOOKINGS = "/bookings";

export const CATALOG: Record<ScenarioId, Scenario> = {
  // ---------- messages ----------
  MSG1: {
    category: "messages", essential: false, collapse: true,
    route: "/messages", channels: ["push"],
    render: (p) => ({title: s(p, "senderName", "Someone"), body: s(p, "text").slice(0, 140)}),
  },

  // ---------- bookings ----------
  BOOK1: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "New booking, paid",
      body: `${s(p, "petName", "A pet")} · ${s(p, "dateLabel")}`.trim()}),
    email: (p) => ({
      subject: `New Pawgo booking · ${s(p, "dateLabel")}`,
      body: {heading: `${s(p, "serviceType", "A booking")} for ${s(p, "petName", "a pet")}`,
        subheading: `${s(p, "dateLabel")} ${s(p, "timeSlot")}`.trim(),
        paragraphs: ["This booking is paid and confirmed. You'll be paid out after it's done."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  BOOK2: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "A booking was cancelled",
      body: `${s(p, "petName", "A pet")} · ${s(p, "dateLabel")}`.trim()}),
    email: (p) => ({
      subject: `Cancelled · ${s(p, "dateLabel")}`,
      body: {heading: `${s(p, "serviceType", "A booking")} was cancelled`,
        subheading: `${s(p, "petName", "A pet")} · ${s(p, "dateLabel")}`,
        paragraphs: ["That slot is free again in your calendar."]},
    }),
  },
  BOOK3: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "New booking request",
      body: `${s(p, "petName", "A pet")} needs a place — ${n(p, "nights")} nights.`}),
    email: (p) => ({
      subject: `New stay request · ${s(p, "petName", "a pet")}`,
      body: {heading: `${s(p, "petName", "A pet")} needs a place`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: ["Open Pawgo to accept or decline. Requests expire on the check-in date."],
        footer: [`You'd earn ${inr(n(p, "subtotal"))}`]},
    }),
  },
  BOOK4: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "Your stay was accepted",
      body: `${s(p, "homeName", "The host")} can host ${s(p, "petName", "your pet")}. Pay to confirm.`}),
    email: (p) => ({
      subject: `Accepted — pay to confirm ${s(p, "petName", "your pet")}'s stay`,
      body: {heading: `${s(p, "homeName", "The host")} accepted your request`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: [`Pay ${inr(n(p, "total"))} in the Pawgo app to confirm. ` +
          "The booking isn't held until it's paid."]},
    }),
  },
  BOOK5: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "Your stay request was declined",
      body: `${s(p, "homeName", "The host")} can't host ${s(p, "petName", "your pet")} then.`}),
    email: (p) => ({
      subject: "Your Pawgo stay request was declined",
      body: {heading: `${s(p, "homeName", "The host")} can't host those dates`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")}`,
        paragraphs: ["Nothing was charged. There are other homes in your area on Pawgo."]},
    }),
  },
  BOOK6: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "A stay is confirmed & paid",
      body: `${s(p, "petName", "A pet")} is booked in at ${s(p, "homeName", "your home")}.`}),
    email: (p) => ({
      subject: `Confirmed · ${s(p, "petName", "a pet")} from ${s(p, "checkInLabel")}`,
      body: {heading: `${s(p, "petName", "A pet")} is booked in`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: [`You'll receive ${inr(n(p, "subtotal"))} after checkout.`]},
    }),
  },
  BOOK7: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push", "email"],
    render: (p) => ({title: "A stay was cancelled",
      body: `${s(p, "petName", "A pet")}'s stay at ${s(p, "homeName", "your home")} was cancelled.`}),
    email: (p) => ({
      subject: `Cancelled · ${s(p, "checkInLabel")}`,
      body: {heading: `${s(p, "petName", "A pet")}'s stay was cancelled`,
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")}`,
        paragraphs: ["Those dates are free again in your calendar."]},
    }),
  },
  BOOK8: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({
      title: `New ${"★".repeat(Math.max(0, Math.min(5, Math.trunc(n(p, "stars")))))} review`,
      body: s(p, "text").trim() || `${s(p, "authorName", "Someone")} rated you.`}),
  },
  BOOK9: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["email"],
    render: (p) => ({title: "Stay request sent",
      body: `${s(p, "homeName", "The host")} · ${n(p, "nights")} nights`}),
    email: (p) => ({
      subject: `We've got your request for ${s(p, "homeName", "a stay")}`,
      body: {heading: "Your stay request is with the host",
        subheading: `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")} · ${n(p, "nights")} nights`,
        paragraphs: [`${s(p, "homeName", "The host")} will accept or decline. ` +
          `Nothing is charged until you pay to confirm — ${inr(n(p, "total"))} if accepted.`],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  BOOK10: {
    category: "bookings", essential: false, collapse: false,
    route: BOOKINGS, channels: ["email"],
    render: (p) => ({title: "Booking created — pay to confirm",
      body: `${s(p, "serviceType", "Service")} · ${s(p, "dateLabel")}`}),
    email: (p) => ({
      subject: `Pay to confirm · ${s(p, "serviceType", "your booking")}`,
      body: {heading: `${s(p, "serviceType", "Your booking")} with ${s(p, "proName", "your pro")}`,
        subheading: `${s(p, "dateLabel")} ${s(p, "timeSlot")}`.trim(),
        paragraphs: [`Pay ${inr(n(p, "total"))} in the Pawgo app to confirm. ` +
          "Unpaid bookings expire on the day of service."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },

  // ---------- woofs ----------
  WOOF1: {
    category: "woofs", essential: false, collapse: false,
    route: "/discover", channels: ["push"],
    render: () => ({title: "It's a match! 🐾", body: "You both woofed. Say hello!"}),
  },

  // ---------- community ----------
  COMM1: {
    category: "community", essential: false, collapse: true,
    route: "/community", channels: ["push"],
    render: (p) => ({title: `${s(p, "authorName", "Someone")} commented on your post`,
      body: s(p, "text").slice(0, 140) || s(p, "postTitle")}),
  },

  // ---------- money (essential) ----------
  PAY1: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `Payment received · ${inr(n(p, "total"))}`,
      body: subject(p)}),
    email: (p) => ({
      subject: `Your Pawgo receipt · ${inr(n(p, "total"))}`,
      body: {heading: s(p, "kind") === "service" ?
        `${s(p, "serviceType", "Service")} with ${s(p, "proName", "your pro")}` :
        `${s(p, "petName", "Your pet")} at ${s(p, "homeName", "the home")}`,
      subheading: s(p, "kind") === "service" ?
        `${s(p, "dateLabel")} ${s(p, "timeSlot")}`.trim() :
        `${s(p, "checkInLabel")} → ${s(p, "checkOutLabel")}`,
      rows: receiptLines(p),
      footer: [`Payment ID ${s(p, "paymentId")}`, `Booking ${s(p, "bookingId")}`,
        "Keep this for your records."]},
    }),
  },
  PAY2: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `${inr(n(p, "amount"))} refunded`,
      body: "It'll reach your account in 5–7 working days."}),
    email: (p) => ({
      subject: `Your Pawgo refund · ${inr(n(p, "amount"))}`,
      body: {heading: `${inr(n(p, "amount"))} is on its way back`,
        paragraphs: [`Your cancellation of ${subject(p)} has been refunded. ` +
          "Refunds usually reach your account in 5–7 working days, depending on your bank."],
        footer: [`Refund ID ${s(p, "refundId")}`, `Booking ${s(p, "bookingId")}`]},
    }),
  },
  PAY3: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: "Cancelled — no refund due",
      body: `${subject(p)} was cancelled too late for a refund.`}),
    email: (p) => ({
      subject: "Your Pawgo cancellation",
      body: {heading: "Cancelled — no refund due",
        paragraphs: [`${subject(p)} has been cancelled.`,
          "Our policy refunds cancellations made before the day itself, so nothing " +
          "is coming back on this one. Nothing further will be charged."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  PAY4: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `${inr(n(p, "amount"))} sent to your bank`,
      body: "Your Pawgo earnings are on the way."}),
    email: (p) => ({
      subject: `Payout sent · ${inr(n(p, "amount"))}`,
      body: {heading: `${inr(n(p, "amount"))} is on its way to your bank`,
        paragraphs: ["Bank transfers usually land within 1–2 working days."],
        footer: [`Booking ${s(p, "bookingId")}`]},
    }),
  },
  PAY5: {
    category: "money", essential: true, collapse: false,
    route: "/payments", channels: ["push", "email"],
    render: (p) => ({title: `${inr(n(p, "amount"))} in earnings waiting`,
      body: "Add your bank details to get paid."}),
    email: (p) => ({
      subject: `${inr(n(p, "amount"))} waiting — add your bank details`,
      body: {heading: `You've earned ${inr(n(p, "amount"))}`,
        paragraphs: ["We can't send it until we know where to send it. " +
          "Add your bank details in Pawgo under Payments and we'll transfer " +
          "everything you're owed on the next payout run."]},
    }),
  },

  // ---------- account (essential) ----------
  ACC1: {
    category: "account", essential: true, collapse: false,
    route: "/profile", channels: ["push", "email"],
    render: () => ({title: "You're Pawgo-verified ✅",
      body: "Your ID check passed. The verified badge is now on your listing."}),
    email: () => ({
      subject: "You're verified on Pawgo",
      body: {heading: "Your ID check passed",
        paragraphs: ["The verified badge now shows on your listing. " +
          "Verified partners get noticeably more bookings."]},
    }),
  },
  ACC2: {
    category: "account", essential: true, collapse: false,
    route: "/profile", channels: ["push", "email"],
    render: (p) => ({title: "Your ID check didn't pass",
      body: s(p, "reason", "Please submit your documents again.")}),
    email: (p) => ({
      subject: "Your Pawgo ID check needs another look",
      body: {heading: "We couldn't verify your documents",
        paragraphs: [s(p, "reason", "Please submit your documents again."),
          "You can re-submit from your profile in the Pawgo app. " +
          "Your listing stays live in the meantime, just without the verified badge."]},
    }),
  },

  // ---------- reminders (push-only) ----------
  REM1: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "Pay today or this booking expires",
      body: `${s(p, "serviceType", "Your booking")} with ${s(p, "proName", "your pro")} · today`}),
  },
  REM2: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "Pay to confirm your stay",
      body: `${s(p, "petName", "Your pet")} checks in tomorrow at ${s(p, "homeName", "the home")}.`}),
  },
  REM3: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "Appointment tomorrow",
      body: `${s(p, "serviceType", "Booking")} · ${s(p, "petName", "your pet")} · ${s(p, "timeSlot")}`}),
  },
  REM4: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: `${s(p, "petName", "Your pet")} checks in tomorrow`,
      body: `${s(p, "homeName", "The home")} · ${n(p, "nights")} nights`}),
  },
  REM5: {
    category: "reminders", essential: false, collapse: false,
    route: BOOKINGS, channels: ["push"],
    render: (p) => ({title: "How was it?",
      body: `Leave ${s(p, "proName", s(p, "homeName", "them"))} a review — it takes 10 seconds.`}),
  },
};
