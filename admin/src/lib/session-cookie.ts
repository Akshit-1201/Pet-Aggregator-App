/**
 * Just the cookie name, in its own module with no `server-only` marker and no
 * firebase-admin import — `middleware.ts` runs on the Edge runtime and cannot
 * load either.
 */
export const SESSION_COOKIE = "pawgo_admin_session";
