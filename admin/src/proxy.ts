import {NextResponse, type NextRequest} from "next/server";
import {SESSION_COOKIE} from "@/lib/session-cookie";

/**
 * Route guard. In Next 16 this file is `proxy.ts`, not `middleware.ts` — the
 * convention was renamed and the named export must be `proxy`.
 *
 * Only checks that a session cookie EXISTS. That is deliberately cheap: this
 * runs on every request including assets, and verifying a session cookie means
 * a round trip to Firebase plus an `adminRoles` read. Real verification happens
 * in `getSession()`, which every page and every server action calls. Treat this
 * as a redirect convenience, never as the access control.
 */
export function proxy(request: NextRequest) {
  const hasCookie = request.cookies.has(SESSION_COOKIE);
  const isLogin = request.nextUrl.pathname.startsWith("/login");

  if (!hasCookie && !isLogin) {
    return NextResponse.redirect(new URL("/login", request.url));
  }
  if (hasCookie && isLogin) {
    return NextResponse.redirect(new URL("/", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
