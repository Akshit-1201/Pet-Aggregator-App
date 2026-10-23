# Plan — legal documents in-app

Spec: `docs/superpowers/specs/2026-10-23-pawgo-legal-documents-design.md`.
Each task: failing test first, then code, `flutter analyze` clean.

1. **`PgBackScope.stepBackWhen` / `onStepBack`.** Tests in
   `test/core/pg_back_scope_test.dart`: true → back runs `onStepBack` and stays
   (system back and `PgBackScope.pop`); false → ordinary native pop
   (`PopScope.canPop` true); a throwing predicate counts as false. Order:
   block → stepBack → confirm → … .
2. **Links + seam.** `lib/core/legal/legal_links.dart` (`LegalDoc`, URL
   constants, `legalUrlsProvider`); `lib/features/legal/document_view.dart`
   (`DocumentView` interface + `documentViewFactoryProvider`);
   `FakeDocumentView` in `test/support/fakes.dart`.
3. **`LegalDocumentScreen` + routes.** Tests
   (`test/features/legal_documents_test.dart`): placeholder when no URL; the
   URL is loaded when set; chevron and system back pop to the opener; with web
   history, back steps back inside the document first, then closes; cold start
   with nothing beneath → Home; load error shows Retry, Retry reloads; the
   engine is told the framework handles back on this screen.
4. **Entry points.** Settings ABOUT rows; sign-up consent line (email + social
   modes). Tests: each opens the right document; back returns to sign-up with
   the typed name still there.
5. **Real WebView.** `lib/features/legal/web_document_view.dart`
   (`webview_flutter` + `url_launcher`), Android `<queries>` for
   mailto/tel/https. Release build + on-device check of back on the emulator.
6. Docs: launch checklist ("paste the two URLs into `legal_links.dart`").
