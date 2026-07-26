import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {CATALOG, PREF_FIELD, type P, type Scenario, type ScenarioId} from "./catalog";
import {sendEmail, type EmailBody} from "./email";

/** Everything with a side effect, injectable so the logic is unit-testable
 *  without Firestore, FCM or Resend. Production values are below. */
export type NotifyDeps = {
  readProfile: (uid: string) => Promise<Record<string, unknown>>;
  readTokens: (uid: string) => Promise<string[]>;
  /** Returns false when the record already existed and the scenario does not
   *  collapse — the caller then skips both channels. This is what makes an
   *  at-least-once redelivery harmless. */
  writeRecord: (uid: string, key: string, data: Record<string, unknown>,
    collapse: boolean) => Promise<boolean>;
  /** Resolves to the list of tokens FCM permanently rejected. */
  sendPush: (uid: string, title: string, body: string, route: string,
    tokens: string[]) => Promise<string[]>;
  pruneTokens: (uid: string, tokens: string[]) => Promise<void>;
  sendMail: (apiKey: string, from: string, to: string, subject: string,
    body: EmailBody) => Promise<boolean>;
  verifiedEmail: (uid: string) => Promise<string>;
};

const production: NotifyDeps = {
  readProfile: async (uid) =>
    (await admin.firestore().collection("users").doc(uid).get()).data() ?? {},

  readTokens: async (uid) => (await admin.firestore()
    .collection("users").doc(uid).collection("fcmTokens").get()).docs.map((d) => d.id),

  writeRecord: async (uid, key, data, collapse) => {
    const ref = admin.firestore()
      .collection("notifications").doc(uid).collection("items").doc(key);
    if (collapse) {
      await ref.set(data);
      return true;
    }
    try {
      await ref.create(data); // fails if the doc exists — our dedupe guard
      return true;
    } catch {
      logger.info("notification already sent, skipping", {uid, key});
      return false;
    }
  },

  sendPush: async (uid, title, body, route, tokens) => {
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title, body},
      data: {route},
      android: {priority: "high", notification: {channelId: "pawgo_default"}},
    });
    const dead: string[] = [];
    res.responses.forEach((r, i) => {
      const code = r.error?.code ?? "";
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token") dead.push(tokens[i]);
    });
    logger.info("push sent", {uid, sent: res.successCount, dead: dead.length});
    return dead;
  },

  pruneTokens: async (uid, tokens) => {
    const db = admin.firestore();
    await Promise.all(tokens.map((t) => db.collection("users").doc(uid)
      .collection("fcmTokens").doc(t).delete().catch(() => undefined)));
  },

  sendMail: (apiKey, from, to, subject, body) => sendEmail(apiKey, from, to, subject, body),

  verifiedEmail: async (uid) => {
    try {
      const u = await admin.auth().getUser(uid);
      return u.emailVerified && u.email ? u.email : "";
    } catch (e) {
      logger.error("verifiedEmail failed", {uid, error: e});
      return "";
    }
  },
};

let deps: NotifyDeps = {...production};
export const setNotifyDeps = (d: Partial<NotifyDeps>) => {
  deps = {...deps, ...d};
};
export const resetNotifyDeps = () => {
  deps = {...production};
};

export type NotifyArgs = {
  scenario: ScenarioId;
  uid: string;
  /** Deterministic dedupe key. Becomes the document id. */
  key: string;
  params?: P;
  apiKey?: string;
  from?: string;
  /** Override the recipient address. Omit to use the verified auth address —
   *  which is what every production caller should do. */
  email?: string;
};

/**
 * The only way anything in Pawgo notifies anyone.
 *
 * Order matters: the record is written FIRST and regardless of preferences.
 * Muting a category opts you out of interruption, not information — your
 * booking history must not vanish from the feed because you turned off push.
 * The record doubles as the send-once guard for both channels.
 *
 * Never throws. A notification that fails must not roll back the booking,
 * message or payment that triggered it.
 */
export async function notify(args: NotifyArgs): Promise<void> {
  const {scenario, uid, key} = args;
  if (!uid || !key) return;
  const spec = CATALOG[scenario];
  if (!spec) return; // unreachable: CATALOG is a typed map
  const params = args.params ?? {};

  let rendered;
  try {
    rendered = spec.render(params);
  } catch (e) {
    logger.error("notification render failed", {scenario, uid, error: e});
    return;
  }

  let fresh = true;
  try {
    fresh = await deps.writeRecord(uid, key, {
      scenario,
      category: spec.category,
      title: rendered.title,
      body: rendered.body,
      route: spec.route,
      createdAt: Date.now(),
      read: false,
    }, spec.collapse);
  } catch (e) {
    // Losing the feed row is bad; losing the notification entirely is worse.
    logger.error("notification record write failed", {scenario, uid, key, error: e});
  }
  if (!fresh) return;

  // The two channels are independent: neither failure may suppress the other.
  await Promise.all([
    spec.channels.includes("push") ? pushIfAllowed(args, spec, rendered) : undefined,
    spec.channels.includes("email") ? mail(args, spec, params) : undefined,
  ]);
}

async function pushIfAllowed(
  args: NotifyArgs,
  spec: Scenario,
  rendered: {title: string; body: string},
) {
  try {
    if (!spec.essential) {
      const profile = await deps.readProfile(args.uid);
      // Absent means ON: accounts predating a flag must not go quiet.
      if (profile[PREF_FIELD[spec.category]] === false) {
        logger.info("push suppressed by preference", {uid: args.uid, category: spec.category});
        return;
      }
    }
    const tokens = await deps.readTokens(args.uid);
    if (tokens.length === 0) return;
    const dead = await deps.sendPush(
      args.uid, rendered.title, rendered.body, spec.route, tokens);
    if (dead.length) await deps.pruneTokens(args.uid, dead);
  } catch (e) {
    logger.error("push failed", {scenario: args.scenario, uid: args.uid, error: e});
  }
}

async function mail(args: NotifyArgs, spec: Scenario, params: P) {
  try {
    if (!spec.email) return;
    const to = args.email ?? await deps.verifiedEmail(args.uid);
    if (!to) return;
    const {subject, body} = spec.email(params);
    await deps.sendMail(args.apiKey ?? "", args.from ?? "", to, subject, body);
  } catch (e) {
    logger.error("email failed", {scenario: args.scenario, uid: args.uid, error: e});
  }
}
