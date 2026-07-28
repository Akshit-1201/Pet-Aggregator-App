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

  static const _homeBranch = 0;

  Future<void> _onBack(BuildContext context) async {
    if (navigationShell.currentIndex != _homeBranch) {
      navigationShell.goBranch(_homeBranch);
      return;
    }
    if (PgExitConfirm.press()) {
      await SystemNavigator.pop();
    } else {
      showPgSnack(context, 'Press back again to exit');
    }
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
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: PgBottomNav(
          currentIndex: navigationShell.currentIndex,
          onTap: (i) => navigationShell.goBranch(i,
              initialLocation: i == navigationShell.currentIndex),
        ),
      ),
    );
  }
}
