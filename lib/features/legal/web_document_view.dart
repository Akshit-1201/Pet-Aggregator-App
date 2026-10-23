import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'document_view.dart';

/// [DocumentView] backed by the platform WebView (Android System WebView /
/// WKWebView). The only file that imports `webview_flutter` or `url_launcher`.
class WebDocumentView implements DocumentView {
  final String url;
  final DocumentViewEvents events;
  late final WebViewController _controller;

  WebDocumentView(this.url, this.events) {
    _controller = WebViewController()
      // Published Google Docs and Notion pages render nothing without JS.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: events.onProgress,
        onPageFinished: (_) => events.onPageFinished(),
        onWebResourceError: (e) {
          // A failed image or script inside a page that loaded is not a
          // failed document; only the page itself counts.
          if (e.isForMainFrame ?? true) events.onError();
        },
        onNavigationRequest: _route,
      ));
    _load();
  }

  void _load() {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      events.onError();
      return;
    }
    _controller.loadRequest(uri).catchError((Object e) {
      debugPrint('WebDocumentView: load failed: $e');
      events.onError();
    });
  }

  /// Web links stay inside the viewer (redirects and multi-page documents
  /// work, and back steps through them). mailto:, tel: and anything else a
  /// WebView can't open go to the system app instead.
  NavigationDecision _route(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about') {
      return NavigationDecision.navigate;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object e) {
      debugPrint('WebDocumentView: no app for ${uri.scheme}: $e');
      return false;
    });
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);

  @override
  Future<bool> canGoBack() => _controller.canGoBack();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Future<void> retry() async {
    // After a failed first load there is nothing to reload — start over.
    if (await _controller.currentUrl() == null) {
      _load();
    } else {
      await _controller.reload();
    }
  }
}
