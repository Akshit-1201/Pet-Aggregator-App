import {describe, it, expect, beforeEach, afterEach} from "vitest";
import {notify, setNotifyDeps, resetNotifyDeps} from "./notify";

type Written = {path: string; data: Record<string, unknown>; existed: boolean};

let written: Written[];
let pushed: {uid: string; title: string; tokens: string[]}[];
let emailed: {to: string; subject: string}[];
let profile: Record<string, unknown>;
let tokens: string[];
let existingKeys: Set<string>;

beforeEach(() => {
  written = []; pushed = []; emailed = [];
  profile = {}; tokens = ["tok1"]; existingKeys = new Set();
  setNotifyDeps({
    readProfile: async () => profile,
    readTokens: async () => tokens,
    writeRecord: async (uid, key, data, collapse) => {
      const path = `${uid}/${key}`;
      const existed = existingKeys.has(path);
      if (existed && !collapse) return false;
      existingKeys.add(path);
      written.push({path, data, existed});
      return true;
    },
    sendPush: async (uid, title, body, route, toks) => {
      pushed.push({uid, title, tokens: toks});
      void body; void route;
      return [];
    },
    pruneTokens: async () => undefined,
    sendMail: async (_k, _f, to, subject) => {
      emailed.push({to, subject});
      return true;
    },
    verifiedEmail: async () => "user@example.com",
  });
});

const base = {uid: "u1", key: "k1", apiKey: "re_real", from: "Pawgo <a@b.com>"};

describe("notify", () => {
  it("writes a record, pushes, and emails a push+email scenario", async () => {
    await notify({...base, scenario: "PAY1", params: {kind: "service", total: 440}});
    expect(written).toHaveLength(1);
    expect(written[0].data.scenario).toBe("PAY1");
    expect(written[0].data.category).toBe("money");
    expect(written[0].data.read).toBe(false);
    expect(pushed).toHaveLength(1);
    expect(emailed).toHaveLength(1);
  });

  it("suppresses push when the category preference is off", async () => {
    profile = {notifyBookings: false};
    await notify({...base, scenario: "BOOK4", params: {}});
    expect(pushed).toHaveLength(0);
  });

  it("still writes the record when the preference suppresses the push", async () => {
    profile = {notifyBookings: false};
    await notify({...base, scenario: "BOOK4", params: {}});
    expect(written).toHaveLength(1);
  });

  it("never lets a preference suppress email", async () => {
    profile = {notifyBookings: false};
    await notify({...base, scenario: "BOOK4", params: {}});
    expect(emailed).toHaveLength(1);
  });

  it("sends essential push even with every preference off", async () => {
    profile = {notifyMoney: false, notifyAccount: false, notifyBookings: false};
    await notify({...base, scenario: "ACC1", params: {}});
    expect(pushed).toHaveLength(1);
  });

  it("treats an absent preference field as ON", async () => {
    profile = {};
    await notify({...base, scenario: "REM4", params: {}});
    expect(pushed).toHaveLength(1);
  });

  it("does not resend on a redelivered event", async () => {
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(written).toHaveLength(1);
    expect(pushed).toHaveLength(1);
    expect(emailed).toHaveLength(1);
  });

  it("re-pushes a collapsing scenario but keeps one record", async () => {
    await notify({...base, scenario: "MSG1", key: "chat_c1", params: {text: "hi"}});
    await notify({...base, scenario: "MSG1", key: "chat_c1", params: {text: "again"}});
    expect(pushed).toHaveLength(2);
    expect(written.filter((w) => w.path === "u1/chat_c1")).toHaveLength(2);
  });

  it("sends no push for an email-only scenario", async () => {
    await notify({...base, scenario: "BOOK9", params: {}});
    expect(pushed).toHaveLength(0);
    expect(emailed).toHaveLength(1);
  });

  it("still pushes when email fails", async () => {
    setNotifyDeps({sendMail: async () => {
      throw new Error("resend down");
    }});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(pushed).toHaveLength(1);
  });

  it("still emails when push throws", async () => {
    setNotifyDeps({sendPush: async () => {
      throw new Error("fcm down");
    }});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(emailed).toHaveLength(1);
  });

  it("skips push when the user has no device tokens", async () => {
    tokens = [];
    await notify({...base, scenario: "REM4", params: {}});
    expect(pushed).toHaveLength(0);
  });

  it("skips email when there is no verified address", async () => {
    setNotifyDeps({verifiedEmail: async () => ""});
    await notify({...base, scenario: "PAY1", params: {kind: "service"}});
    expect(emailed).toHaveLength(0);
  });

  it("does nothing at all for an empty uid", async () => {
    await notify({...base, uid: "", scenario: "PAY1", params: {}});
    expect(written).toHaveLength(0);
    expect(pushed).toHaveLength(0);
  });

  it("never throws when the record write fails", async () => {
    setNotifyDeps({writeRecord: async () => {
      throw new Error("firestore down");
    }});
    await expect(notify({...base, scenario: "PAY1", params: {}})).resolves.toBeUndefined();
  });

  afterEach(() => resetNotifyDeps());
});
