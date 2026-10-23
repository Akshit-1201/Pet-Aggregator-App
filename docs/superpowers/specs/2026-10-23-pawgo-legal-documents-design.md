# Legal documents in-app — Privacy Policy + Terms & Conditions

_2026-10-23 · owner request: "add the privacy policy and terms and conditions
link to the app… I will add the document to the links later which can be viewed
in the app and also make sure the back gesture and button works properly."_

## Why

Both stores need a privacy policy reachable inside the app (Apple requires it;
Play recommends it and requires one in the listing). Terms are standard at
account creation. The documents don't exist yet — the owner will host them and
paste the URLs later — so the app must behave well with no URL set.

## Decisions

1. **Where the URLs live:** `lib/core/legal/legal_links.dart` — one constant per
   document, empty for now. Filling them in is a one-line change per document;
   no other code changes. Exposed through `legalUrlsProvider` so tests can set
   them.
2. **Viewer = an in-app screen with a WebView** (`webview_flutter`), not a
   Chrome Custom Tab / SFSafariViewController. Reason: the owner asked for back
   to work properly, and only a Flutter screen gives us the app's own header +
   chevron and full control of back. A Custom Tab's back is owned by the
   browser.
3. **Routes:** `/privacy-policy` and `/terms`, public (not in `_protected`):
   reachable from sign-up (signed out) and Settings (signed in). Always
   `push`ed, so back returns to the screen that opened them with its state
   intact (a half-filled sign-up form survives).
4. **Back, one resolver for chevron + hardware/gesture back:**
   - If the WebView has history (the person tapped a link inside the
     document), back goes back one page **inside the document**.
   - Otherwise back closes the screen (normal pop; native predictive-back
     animation preserved because nothing is intercepted then).
   - Nothing beneath (cold deep link): `upToIfEmpty: Routes.home` — the router
     already bounces signed-out users from Home to Welcome.
   Implemented as a new, general `PgBackScope` option: `stepBackWhen` (pure,
   sync predicate) + `onStepBack`. The screen keeps a `_canGoBack` flag,
   refreshed from the WebView after every navigation, because `canGoBack()` is
   async and predicates must be sync.
5. **Links inside the document:** `http(s)` navigates inside the viewer (so
   redirects and multi-page docs such as Google Docs/Notion work). `mailto:`,
   `tel:` and other schemes open the system app via `url_launcher` — a
   WebView can't handle them.
6. **States:** no URL → friendly placeholder ("…will be published here soon");
   loading → thin progress bar under the header; load failure → message +
   Retry. JavaScript enabled (Google Docs / Notion need it).
7. **Entry points:** Settings → ABOUT gains "Privacy policy" and "Terms &
   conditions" rows. Sign-up (both the email form and the Google/Apple/phone
   "Finish setting up" mode) gains "By continuing, you agree to our Terms &
   Conditions and Privacy Policy." with both phrases tappable.
8. **Seam for tests:** WebViews can't render under `flutter_test`, same as
   Maps. `documentViewFactoryProvider` builds a `DocumentView` (widget +
   `canGoBack`/`goBack`/`reload` + callbacks). The real implementation is the
   only file importing `webview_flutter`/`url_launcher`; tests use a fake with
   scriptable history.

## Out of scope

Bundling the documents as offline assets, versioned consent records
("accepted terms v3 on date X"), and a re-consent prompt when terms change.
