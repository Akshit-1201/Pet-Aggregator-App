import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'web_document_view.dart';

/// A page of web content shown inside a screen, with its own back history.
///
/// A seam for the same reason as the Maps view: platform WebViews cannot
/// render under `flutter_test`, so tests swap in a fake through
/// [documentViewFactoryProvider]. Only `web_document_view.dart` imports the
/// WebView SDK.
abstract class DocumentView {
  Widget build(BuildContext context);

  /// Whether the person followed a link inside the document, so back should
  /// step back a page rather than leave the screen.
  Future<bool> canGoBack();
  Future<void> goBack();

  /// Tries again after a failed load.
  Future<void> retry();
}

/// What the view reports back to its screen.
class DocumentViewEvents {
  /// 0–100 while a page loads.
  final void Function(int percent) onProgress;

  /// A page finished loading — history may have changed.
  final VoidCallback onPageFinished;

  /// The page itself could not be loaded (offline, DNS, 404 page aside).
  final VoidCallback onError;

  const DocumentViewEvents({required this.onProgress, required this.onPageFinished,
      required this.onError});
}

typedef DocumentViewFactory = DocumentView Function(String url, DocumentViewEvents events);

final documentViewFactoryProvider =
    Provider<DocumentViewFactory>((_) => WebDocumentView.new);
