"use client";
import {getApp, getApps, initializeApp} from "firebase/app";
import {GoogleAuthProvider, getAuth, signInWithPopup} from "firebase/auth";

/**
 * Client SDK, used for exactly one thing: the Google popup that produces an ID
 * token. Everything after that is server-side.
 *
 * These values are public by design — the same config ships inside the Android
 * app. They identify the project; they do not grant access. Authorisation is
 * the `adminRoles` lookup in session.ts.
 */
const config = {
  apiKey: "AIzaSyCjymoaTQzNSxmSBKc5yVdfZto5DxOdbg8",
  authDomain: "pet-aggregator-app.firebaseapp.com",
  projectId: "pet-aggregator-app",
  messagingSenderId: "280616341211",
  appId: "1:280616341211:web:2a72cc1695b866e98a46fe",
};

export async function signInWithGoogleForIdToken(): Promise<string> {
  const app = getApps().length ? getApp() : initializeApp(config);
  const provider = new GoogleAuthProvider();
  // Always show the chooser: staff often have a personal Google session in the
  // same browser, and silently reusing it makes "wrong account" errors baffling.
  provider.setCustomParameters({prompt: "select_account"});
  const cred = await signInWithPopup(getAuth(app), provider);
  return cred.user.getIdToken();
}
