"use server";
import {createSession, destroySession} from "@/lib/session";

export type LoginResult = {ok: true} | {ok: false; error: string};

export async function signIn(idToken: string): Promise<LoginResult> {
  try {
    await createSession(idToken);
    return {ok: true};
  } catch (e) {
    return {ok: false, error: e instanceof Error ? e.message : "Sign-in failed."};
  }
}

export async function signOut() {
  await destroySession();
}
