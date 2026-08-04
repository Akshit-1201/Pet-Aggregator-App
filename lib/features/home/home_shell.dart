import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/exit_confirm.dart';
import '../../core/widgets/pg_bottom_nav.dart';
import '../../core/widgets/pg_snackbar.dart';

/// Owns back for all five tabs, in one place.
///
/// Back on a non-Home tab returns to Home rather than closing the app — the
/// behaviour whose absence made pressing back on Profile exit Pawgo. On Home
/// it takes two presses inside [PgExitConfirm.window], so an accidental press
/// mid-booking cannot drop someone out.
class HomeShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const HomeShell({super.key, required this.navigationShell});

  /// Index of the Home branch — where every non-Home tab's back (hardware
  /// and its on-screen chevron alike) returns to.
  static const homeBranch = 0;

  /// The "press back again to exit" path, shared by hardware back on the
  /// Home tab and Home's own on-screen chevron so the two can never diverge.
  static Future<void> confirmExit(BuildContext context) async {
    if (PgExitConfirm.press()) {
      await SystemNavigator.pop();
    } else {
      showPgSnack(context, 'Press back again to exit');
    }
  }

  Future<void> _onBack(BuildContext context) async {
    if (navigationShell.currentIndex != homeBranch) {
      navigationShell.goBranch(homeBranch);
      return;
    }
    await confirmExit(context);
  }

  /// Tells the engine the framework handles back, no matter what the branch
  /// Navigators below say.
  ///
  /// Android only routes back into Dart when the framework has claimed it via
  /// `SystemNavigator.setFrameworkHandlesBack(true)`. `WidgetsApp` derives that
  /// flag from the last [NavigationNotification] to reach it — and a
  /// [PopScope] only influences the notification of the Navigator that owns
  /// its route. Ours registers on the *root* Navigator's shell route, while
  /// `navigationShell` mounts a separate Navigator per branch. A branch sitting
  /// at its root dispatches `canHandlePop: false`, and the root Navigator
  /// forwards a child's notification unchanged whenever its own `canPop()` is
  /// false (`_NavigatorState.build`); it never consults its route's
  /// `popDisposition`, which is the only thing [PopScope] affects. So the
  /// false reached the engine, Android finished the Activity itself, and
  /// [_onBack] never ran — back quit Pawgo from any non-Home tab.
  ///
  /// Correcting it here is sound because [_onBack] is unconditional: every
  /// back while this shell is mounted either switches branch or runs the
  /// exit confirmation, so `true` is never a lie. Re-dispatching from
  /// [context] — an ancestor of this listener — is the same technique
  /// `_NavigatorState` uses to widen a nested Navigator's claim, and cannot
  /// re-enter this listener.
  ///
  /// Guarded by a widget test asserting the flag the engine receives; the
  /// suite's other back tests call `binding.handlePopRoute()`, which bypasses
  /// this gate entirely and so passed all the way through the bug.
  bool _claimBack(BuildContext context, NavigationNotification n) {
    if (n.canHandlePop) return false; // already claimed — let it through
    const NavigationNotification(canHandlePop: true).dispatch(context);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Always intercept: a tab root has nothing above it, so Flutter's default
      // is to close the app — which is exactly what we are preventing.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBack(context);
      },
      child: NotificationListener<NavigationNotification>(
        onNotification: (n) => _claimBack(context, n),
        child: Scaffold(
          body: navigationShell,
          bottomNavigationBar: PgBottomNav(
            currentIndex: navigationShell.currentIndex,
            onTap: (i) => navigationShell.goBranch(i,
                initialLocation: i == navigationShell.currentIndex),
          ),
        ),
      ),
    );
  }
}
