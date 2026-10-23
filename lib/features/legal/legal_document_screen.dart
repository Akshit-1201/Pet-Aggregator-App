import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/legal/legal_links.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import 'document_view.dart';

/// The Privacy Policy or Terms, shown inside the app.
///
/// Back — chevron, button and gesture alike — first steps back through any
/// link the person followed inside the document, then leaves to whatever
/// opened it. Opened cold with nothing beneath, it goes Home (the router sends
/// a signed-out user on to Welcome).
class LegalDocumentScreen extends ConsumerStatefulWidget {
  final LegalDoc doc;
  const LegalDocumentScreen({super.key, required this.doc});

  @override
  ConsumerState<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends ConsumerState<LegalDocumentScreen> {
  DocumentView? _view;
  int _progress = 0;
  bool _failed = false;

  /// Mirrors the view's async canGoBack(), because PgBackScope's predicates
  /// must be synchronous. Refreshed after every page load.
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    final url = ref.read(legalUrlsProvider)[widget.doc] ?? '';
    if (url.isNotEmpty) {
      _view = ref.read(documentViewFactoryProvider)(url, DocumentViewEvents(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: _refreshHistory,
        onError: () {
          if (mounted) setState(() => _failed = true);
        },
      ));
    }
  }

  Future<void> _refreshHistory() async {
    final view = _view;
    if (view == null) return;
    final can = await view.canGoBack();
    if (mounted) setState(() { _canGoBack = can; _progress = 100; });
  }

  Future<void> _stepBack() async {
    await _view?.goBack();
    await _refreshHistory();
  }

  Future<void> _retry() async {
    setState(() { _failed = false; _progress = 0; });
    await _view?.retry();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final view = _view;
    return PgBackScope(
      upToIfEmpty: Routes.home,
      stepBackWhen: () => _canGoBack,
      onStepBack: _stepBack,
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Column(children: [
            Builder(builder: (ctx) =>
                PgAppBar(title: widget.doc.title, onBack: () => PgBackScope.pop(ctx))),
            if (view != null && !_failed && _progress < 100)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
                color: c.brand,
                backgroundColor: c.border,
              ),
            Expanded(
              child: view == null
                  ? _Message(
                      icon: '📄',
                      text: 'Our ${widget.doc.name} will be published here soon.')
                  : _failed
                      ? _Message(
                          icon: '📡',
                          text: "Couldn't load the ${widget.doc.name}. "
                              'Check your connection and try again.',
                          action: TextButton(
                            onPressed: _retry,
                            child: Text('Retry',
                                style: PgText.inter(14, FontWeight.w700, color: c.brand)),
                          ))
                      : view.build(context),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String icon, text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w500, color: c.muted, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ]),
      ),
    );
  }
}
