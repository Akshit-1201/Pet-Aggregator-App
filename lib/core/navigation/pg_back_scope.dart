import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../widgets/pg_snackbar.dart';
import 'exit_confirm.dart';

typedef BackPredicate = bool Function();

/// Declares what back does on one screen — for the hardware/gesture back AND
/// the on-screen chevron, which route through the same resolver here.
///
/// Resolution order is **block → confirm → confirmExit → upTo → pop →
/// upToIfEmpty → exit**. Omit every option and this is an ordinary pop, so
/// wrapping a screen costs nothing.
///
/// Wrap the widget your screen's `build` returns, not something above the
/// `State` — a `setState` must rebuild this so the predicates re-evaluate.
class PgBackScope extends StatelessWidget {
  final Widget child;

  /// Forced destination — wins even when a poppable stack exists. Use this
  /// only where a real pop would be wrong (e.g. it would re-enter a finished
  /// checkout): screens reached exclusively via `go`. Always a `Routes.*`
  /// constant: go_router throws on an unknown path, so a constant turns a
  /// typo into a compile error.
  final String? upTo;

  /// Where to go when there is nothing to pop — a cold-start deep link, or
  /// arrival via `go`. Unlike [upTo], a normal pop wins when a stack exists,
  /// so a screen pushed from a live parent returns to it with its state
  /// intact. Use this for screens reached by `push` from a live parent.
  final String? upToIfEmpty;

  /// For screens with nowhere to go up to. Shows "Press back again to exit"
  /// and exits only on a second press inside [PgExitConfirm.window].
  final bool confirmExit;

  /// Ask before leaving. Only where leaving destroys real work — prompting on
  /// a two-field form trains people to dismiss the dialog unread.
  final BackPredicate? confirmWhen;
  final String confirmTitle;
  final String confirmMessage;

  /// Refuse back outright, e.g. while a payment is verifying. A predicate that
  /// also performs its own side effect (e.g. onboarding stepping to the
  /// previous page) is fine here — see the evaluation-order note on
  /// [_nativePop] for why that doesn't fire on unrelated rebuilds.
  final BackPredicate? blockWhen;

  /// Shown when [blockWhen] refuses back. Leave empty to suppress the snack
  /// entirely — for a block that already communicates itself another way
  /// (onboarding's page-back animation).
  final String blockMessage;

  /// Runs after any confirm and immediately before navigating — for a side
  /// effect that must happen on the way out, e.g. signing out before the
  /// verify-email gate redirects. Guarded by `context.mounted` after the
  /// await, same as everything else in [_resolve].
  final Future<void> Function()? onBeforeLeave;

  const PgBackScope({
    super.key,
    required this.child,
    this.upTo,
    this.upToIfEmpty,
    this.confirmExit = false,
    this.confirmWhen,
    this.confirmTitle = 'Discard changes?',
    this.confirmMessage = "You haven't saved this yet. Leaving now loses it.",
    this.blockWhen,
    this.blockMessage = 'Please wait — this is still in progress.',
    this.onBeforeLeave,
  });

  /// Runs the nearest scope's resolver — the same path the OS back takes.
  /// `PgAppBar.onBack` calls this so the button and the gesture cannot drift.
  static Future<void> pop(BuildContext context) async {
    final data = context.getInheritedWidgetOfExactType<_PgBackScopeData>();
    if (data != null) return data.resolve();
    if (context.canPop()) context.pop();
  }

  /// A predicate that throws is treated as false: a broken check must never
  /// trap someone on a screen with no way out.
  static bool _safe(BackPredicate? p) {
    if (p == null) return false;
    try {
      return p();
    } catch (_) {
      return false;
    }
  }

  // Deliberately does not mention `upToIfEmpty`: it only applies when there
  // is nothing to pop, so a poppable stack must still let the OS handle back
  // natively (predictive-back animation intact) rather than being
  // intercepted here.
  //
  // `confirmExit`/`upTo` are checked before `blockWhen`/`confirmWhen` on
  // purpose: this getter reruns on every rebuild of the screen (any parent
  // `setState` reconstructs this widget), not only on an actual back press.
  // `confirmExit`/`upTo` are plain fields, safe to re-read for free, and once
  // either rules native pop out the `&&` chain short-circuits — so a
  // `blockWhen` that also performs a side effect (onboarding's page-back)
  // never runs here, only from an actual back attempt in [_resolve].
  bool _nativePop(BuildContext context) =>
      !confirmExit &&
      upTo == null &&
      !_safe(blockWhen) &&
      !_safe(confirmWhen) &&
      context.canPop();

  Future<void> _resolve(BuildContext context) async {
    if (_safe(blockWhen)) {
      if (blockMessage.isNotEmpty) showPgSnack(context, blockMessage);
      return;
    }

    if (_safe(confirmWhen)) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (leave != true || !context.mounted) return;
    }

    if (onBeforeLeave != null) {
      await onBeforeLeave!();
      if (!context.mounted) return;
    }

    if (confirmExit) {
      if (PgExitConfirm.press()) {
        await SystemNavigator.pop();
      } else {
        showPgSnack(context, 'Press back again to exit');
      }
      return;
    }

    if (upTo != null) {
      context.go(upTo!);
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    if (upToIfEmpty != null) {
      context.go(upToIfEmpty!);
      return;
    }
    // Nothing above this screen and no destination declared: leave the app.
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _nativePop(context),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _resolve(context);
      },
      child: _PgBackScopeData(resolve: () => _resolve(context), child: child),
    );
  }
}

class _PgBackScopeData extends InheritedWidget {
  final Future<void> Function() resolve;
  const _PgBackScopeData({required this.resolve, required super.child});

  @override
  bool updateShouldNotify(_PgBackScopeData old) => true;
}
