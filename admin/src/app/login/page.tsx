"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {signInWithGoogleForIdToken} from "@/lib/firebase-client";
import {signIn} from "./actions";

export default function LoginPage() {
  const router = useRouter();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function onSignIn() {
    setBusy(true);
    setError("");
    try {
      const idToken = await signInWithGoogleForIdToken();
      const result = await signIn(idToken);
      if (result.ok) {
        router.replace("/");
        router.refresh();
      } else {
        setError(result.error);
      }
    } catch (e) {
      // A closed popup is a normal user action, not an error worth shouting about.
      const code = (e as {code?: string})?.code ?? "";
      if (code === "auth/popup-closed-by-user" || code === "auth/cancelled-popup-request") {
        setError("");
      } else {
        setError("Could not reach Google. Please try again.");
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#FBF1E8] p-6">
      <div className="w-full max-w-sm rounded-3xl bg-white p-8 shadow-sm">
        <div className="text-2xl font-extrabold text-[#F0871E]">Pawgo</div>
        <h1 className="mt-1 text-lg font-bold text-neutral-900">Admin panel</h1>
        <p className="mt-2 text-sm leading-relaxed text-neutral-500">
          Staff access only. Sign in with the Google account that was added to
          the admin list.
        </p>

        <button
          onClick={onSignIn}
          disabled={busy}
          className="mt-6 w-full rounded-xl bg-[#F0871E] px-4 py-3 text-sm font-bold text-white transition hover:bg-[#e0770f] disabled:opacity-60"
        >
          {busy ? "Signing in…" : "Continue with Google"}
        </button>

        {error && (
          <p className="mt-4 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
        )}
      </div>
    </main>
  );
}
