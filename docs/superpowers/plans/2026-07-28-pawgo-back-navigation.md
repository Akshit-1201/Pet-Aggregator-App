# Pawgo Slice 22: App-wide back navigation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every one of the 38 screens a defined back behaviour on both the hardware/gesture back and the on-screen chevron, so back never exits the app unexpectedly, never strands a user, and never walks back into a completed checkout.

**Architecture:** One shared `PgBackScope` widget wraps any screen needing non-default back handling, taking up to four optional behaviours resolved in order **block → confirm → upTo → pop**. `canPop` is computed, so plain screens keep Flutter's native (predictive) back and only screens that need interception get it. `PgBackScope.pop(context)` runs the same resolver the OS back invokes, and `PgAppBar.onBack` calls it — so the button and the gesture cannot diverge. Tab behaviour lives once in `HomeShell`.

**Tech Stack:** Flutter/Dart ^3.12.2, `go_router`, `flutter_riverpod` 3.x. No new packages.

**Spec:** `docs/superpowers/specs/2026-07-28-pawgo-back-navigation-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **No new packages.** Everything here uses `flutter/services.dart` (`SystemNavigator`), `go_router`, and existing `Pg*` widgets.
- **`canPop` is computed, never hardcoded `false`.** Hardcoding it intercepts every back press app-wide and silently disables Android 14 predictive back on all 38 screens. The formula is fixed: `!blocked && !dirty && !confirmExit && upTo == null && context.canPop()`.
- **Resolution order is block → confirm → upTo → pop.** Blocked wins over dirty; no dialog is shown when blocked.
- **`upTo` values are `Routes.*` constants only** — never string literals. go_router throws on an unknown path, so a constant makes a typo a compile error.
- **A predicate that throws is treated as `false`.** A broken `confirmWhen`/`blockWhen` must never trap a user on a screen.
- **The exit-confirm window is 2 seconds**, shared by `HomeShell` and `PgBackScope(confirmExit: true)` through one helper. Two implementations of this will drift.
- **`PgBackScope` wraps the widget a screen's `build` returns**, so a `setState` in the screen rebuilds it and the predicates re-evaluate. Do not hoist it above the screen's `State`.
- Riverpod 3.x uses `.value` (not `valueOrNull`); async handlers guard `context.mounted` across every await; widget tests use `pumpPgApp` from `test/support/pump.dart` with fakes from `test/support/fakes.dart`.
- **Every task ends green:** `flutter analyze` clean + `flutter test` passing, then commit. **Do NOT push. Do NOT deploy. Do NOT run any `firebase` command.**

## A note on the test code in Tasks 6–10

Tasks 1–5 and 9 contain complete, runnable test code. **Tasks 6, 7, 8 and 10 give the test names, the exact assertions, and the fixture file to copy from, but not full bodies** — those screens need provider overrides and fixtures that differ per screen, and inventing them here would produce code that looks authoritative and does not compile.

For each of those tasks: read the named existing test file first, copy its setup verbatim, then write the assertion given. If a test as specified cannot be made to pass, that is a finding about the design — report it rather than weakening the assertion.

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/navigation/exit_confirm.dart` (new) | The 2-second double-press window. Static, shared by the shell and `PgBackScope`. |
| `lib/core/navigation/pg_back_scope.dart` (new) | The widget, the resolver, and `PgBackScope.pop`. |
| `lib/features/home/home_shell.dart` (modify) | Tab → Home → confirmed exit. Becomes stateful. |
| `lib/core/widgets/pg_app_bar.dart` (unchanged) | Already takes `onBack`; screens pass `PgBackScope.pop`. |
| ~20 screen files (modify) | Wrap in `PgBackScope`, declare intent. |

---

### Task 1: The exit-confirm window

Smallest independent unit, and both later consumers depend on it.

**Files:**
- Create: `lib/core/navigation/exit_confirm.dart`
- Create: `test/core/exit_confirm_test.dart`

**Interfaces:**
- Produces: `class PgExitConfirm` with `static bool press({DateTime? now})` (returns `true` when the app should exit), `static void reset()`, and `static const Duration window = Duration(seconds: 2)`.

`now` is injectable so the window is testable without real waiting.

- [ ] **Step 1: Write the failing test**

Create `test/core/exit_confirm_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';

void main() {
  setUp(PgExitConfirm.reset);

  test('a single press never exits', () {
    expect(PgExitConfirm.press(now: DateTime(2026, 7, 28, 10, 0, 0)), isFalse);
  });

  test('a second press inside the window exits', () {
    final t = DateTime(2026, 7, 28, 10, 0, 0);
    expect(PgExitConfirm.press(now: t), isFalse);
    expect(PgExitConfirm.press(now: t.add(const Duration(milliseconds: 1500))), isTrue);
  });

  test('a second press after the window does not exit', () {
    final t = DateTime(2026, 7, 28, 10, 0, 0);
    expect(PgExitConfirm.press(now: t), isFalse);
    expect(PgExitConfirm.press(now: t.add(const Duration(seconds: 3))), isFalse);
  });

  test('a late press restarts the window rather than exiting on the next', () {
    final t = DateTime(2026, 7, 28, 10, 0, 0);
    PgExitConfirm.press(now: t);
    PgExitConfirm.press(now: t.add(const Duration(seconds: 3))); // restarts
    expect(PgExitConfirm.press(now: t.add(const Duration(seconds: 4))), isTrue);
  });

  test('reset clears a pending press', () {
    final t = DateTime(2026, 7, 28, 10, 0, 0);
    PgExitConfirm.press(now: t);
    PgExitConfirm.reset();
    expect(PgExitConfirm.press(now: t.add(const Duration(milliseconds: 100))), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/exit_confirm_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pet_aggregator_app/core/navigation/exit_confirm.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/core/navigation/exit_confirm.dart`:

```dart
/// The "press back again to exit" window.
///
/// Static rather than injected because it is genuinely app-global: the shell
/// and any screen with nowhere to go up to share one window, and two
/// implementations of it would drift. `now` is injectable so the window is
/// testable without real waiting, and [reset] exists so tests start clean.
class PgExitConfirm {
  PgExitConfirm._();

  static const Duration window = Duration(seconds: 2);

  static DateTime? _lastPress;

  /// Records a back press. Returns true when the app should exit — i.e. this
  /// is the second press inside [window].
  static bool press({DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = _lastPress;
    _lastPress = at;
    return last != null && at.difference(last) < window;
  }

  static void reset() => _lastPress = null;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/exit_confirm_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze`
Expected: No issues found

```bash
git add lib/core/navigation/exit_confirm.dart test/core/exit_confirm_test.dart
git commit -m "feat: shared press-back-again-to-exit window"
```

---

### Task 2: `PgBackScope` — pop, upTo, and computed canPop

The core widget, without the guards. Guards land in Task 3 so each has its own review gate.

**Files:**
- Create: `lib/core/navigation/pg_back_scope.dart`
- Create: `test/core/pg_back_scope_test.dart`

**Interfaces:**
- Consumes: `PgExitConfirm` from Task 1.
- Produces:
```dart
typedef BackPredicate = bool Function();

class PgBackScope extends StatelessWidget {
  const PgBackScope({
    super.key,
    required Widget child,
    String? upTo,
    bool confirmExit = false,
    BackPredicate? confirmWhen,
    String confirmTitle,
    String confirmMessage,
    BackPredicate? blockWhen,
    String blockMessage,
  });

  static Future<void> pop(BuildContext context);
}
```

- [ ] **Step 1: Write the failing test**

Create `test/core/pg_back_scope_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/navigation/pg_back_scope.dart';

/// A two-route app so we can test both "there is a stack" and "there is not".
GoRouter _router({required Widget Function() detail, String initial = '/detail'}) =>
    GoRouter(initialLocation: initial, routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('ROOT'))),
      GoRoute(path: '/parent', builder: (_, _) => const Scaffold(body: Text('PARENT'))),
      GoRoute(path: '/detail', builder: (_, _) => detail()),
    ]);

Future<void> _pump(WidgetTester t, GoRouter r) async {
  await t.pumpWidget(MaterialApp.router(routerConfig: r));
  await t.pumpAndSettle();
}

/// Simulates the Android system back button.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('with no options and a stack, back pops natively', (t) async {
    final r = _router(detail: () => const PgBackScope(
        child: Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    expect(find.text('PARENT'), findsOneWidget);

    await _systemBack(t);
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('canPop is true when nothing needs interception', (t) async {
    final r = _router(detail: () => const PgBackScope(
        child: Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    // Predictive back depends on canPop being true rather than us intercepting.
    final scope = t.widget<PopScope>(find.byType(PopScope).last);
    expect(scope.canPop, isTrue);
  });

  testWidgets('upTo wins even when there IS a poppable stack', (t) async {
    final r = _router(detail: () => const PgBackScope(
        upTo: '/parent', child: Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/');
    await t.pumpAndSettle();
    expect(find.text('ROOT'), findsOneWidget);

    await _systemBack(t);
    // Not back to DETAIL — upTo forced the destination.
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('upTo is used when there is NO stack (cold-start deep link)', (t) async {
    final r = _router(detail: () => const PgBackScope(
        upTo: '/parent', child: Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    expect(find.text('DETAIL'), findsOneWidget);

    await _systemBack(t);
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('canPop is false when upTo is set, so we intercept', (t) async {
    final r = _router(detail: () => const PgBackScope(
        upTo: '/parent', child: Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    final scope = t.widget<PopScope>(find.byType(PopScope).last);
    expect(scope.canPop, isFalse);
  });

  testWidgets('PgBackScope.pop runs the same resolver as system back', (t) async {
    late BuildContext inner;
    final r = _router(detail: () => PgBackScope(
        upTo: '/parent',
        child: Scaffold(body: Builder(builder: (c) {
          inner = c;
          return const Text('DETAIL');
        }))));
    await _pump(t, r);

    await PgBackScope.pop(inner);
    await t.pumpAndSettle();
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('PgBackScope.pop without a scope falls back to a plain pop', (t) async {
    late BuildContext inner;
    final r = _router(detail: () => Scaffold(body: Builder(builder: (c) {
          inner = c;
          return const Text('DETAIL');
        })));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();

    await PgBackScope.pop(inner);
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/pg_back_scope_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../pg_back_scope.dart'`

- [ ] **Step 3: Write the widget**

Create `lib/core/navigation/pg_back_scope.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../widgets/pg_snackbar.dart';
import 'exit_confirm.dart';

typedef BackPredicate = bool Function();

/// Declares what back does on one screen — for the hardware/gesture back AND
/// the on-screen chevron, which route through the same resolver here.
///
/// Resolution order is **block → confirm → upTo → pop**. Omit every option and
/// this is an ordinary pop, so wrapping a screen costs nothing.
///
/// Wrap the widget your screen's `build` returns, not something above the
/// `State` — a `setState` must rebuild this so the predicates re-evaluate.
class PgBackScope extends StatelessWidget {
  final Widget child;

  /// Forced destination, and the fallback when there is nothing to pop.
  /// Always a `Routes.*` constant: go_router throws on an unknown path, so a
  /// constant turns a typo into a compile error.
  final String? upTo;

  /// For screens with nowhere to go up to. Shows "Press back again to exit"
  /// and exits only on a second press inside [PgExitConfirm.window].
  final bool confirmExit;

  /// Ask before leaving. Only where leaving destroys real work — prompting on
  /// a two-field form trains people to dismiss the dialog unread.
  final BackPredicate? confirmWhen;
  final String confirmTitle;
  final String confirmMessage;

  /// Refuse back outright, e.g. while a payment is verifying.
  final BackPredicate? blockWhen;
  final String blockMessage;

  const PgBackScope({
    super.key,
    required this.child,
    this.upTo,
    this.confirmExit = false,
    this.confirmWhen,
    this.confirmTitle = 'Discard changes?',
    this.confirmMessage = "You haven't saved this yet. Leaving now loses it.",
    this.blockWhen,
    this.blockMessage = 'Please wait — this is still in progress.',
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

  bool _nativePop(BuildContext context) =>
      !_safe(blockWhen) &&
      !_safe(confirmWhen) &&
      !confirmExit &&
      upTo == null &&
      context.canPop();

  Future<void> _resolve(BuildContext context) async {
    if (_safe(blockWhen)) {
      showPgSnack(context, blockMessage);
      return;
    }

    if (_safe(confirmWhen)) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep editing')),
            TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Discard')),
          ],
        ),
      );
      if (leave != true || !context.mounted) return;
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
      child: _PgBackScopeData(
        resolve: () => _resolve(context),
        child: child,
      ),
    );
  }
}

class _PgBackScopeData extends InheritedWidget {
  final Future<void> Function() resolve;
  const _PgBackScopeData({required this.resolve, required super.child});

  @override
  bool updateShouldNotify(_PgBackScopeData old) => true;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/pg_back_scope_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze`
Expected: No issues found

```bash
git add lib/core/navigation/pg_back_scope.dart test/core/pg_back_scope_test.dart
git commit -m "feat: PgBackScope - upTo, computed canPop, shared resolver"
```

---

### Task 3: `PgBackScope` guards — confirm, block, exit-confirm

**Files:**
- Modify: `test/core/pg_back_scope_test.dart` (append)

No production change is expected — Task 2's implementation already contains the guards. These tests pin them. **If a test fails, fix `pg_back_scope.dart`; do not weaken the test.**

**Interfaces:**
- Consumes: everything from Task 2.

- [ ] **Step 1: Write the failing tests**

Append inside `void main()` in `test/core/pg_back_scope_test.dart`:

```dart
  testWidgets('confirmWhen false pops silently, no dialog', (t) async {
    final r = _router(detail: () => PgBackScope(
        confirmWhen: () => false, child: const Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('confirmWhen true shows a dialog; Keep editing stays put', (t) async {
    final r = _router(detail: () => PgBackScope(
        confirmWhen: () => true, child: const Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('PARENT'), findsOneWidget); // never left
  });

  testWidgets('confirmWhen true then Discard leaves the screen', (t) async {
    final r = _router(detail: () => PgBackScope(
        confirmWhen: () => true, child: const Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    await _systemBack(t);

    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('blockWhen refuses back and shows the message', (t) async {
    final r = _router(detail: () => PgBackScope(
        blockWhen: () => true,
        blockMessage: 'Payment in progress',
        child: const Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.text('PARENT'), findsOneWidget); // still here
    expect(find.text('Payment in progress'), findsOneWidget);
  });

  testWidgets('blocked wins over dirty — no dialog is shown', (t) async {
    final r = _router(detail: () => PgBackScope(
        blockWhen: () => true,
        confirmWhen: () => true,
        child: const Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('a throwing predicate is treated as false, never traps', (t) async {
    final r = _router(detail: () => PgBackScope(
        blockWhen: () => throw StateError('boom'),
        child: const Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.text('DETAIL'), findsOneWidget); // it popped
  });

  testWidgets('confirmExit shows the toast first, does not leave', (t) async {
    PgExitConfirm.reset();
    final r = _router(detail: () => const PgBackScope(
        confirmExit: true, child: Scaffold(body: Text('DETAIL'))));
    await _pump(t, r);

    await _systemBack(t);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('DETAIL'), findsOneWidget);
  });
```

Add to the imports at the top of the file:

```dart
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
```

- [ ] **Step 2: Run the tests**

Run: `flutter test test/core/pg_back_scope_test.dart`
Expected: PASS — 14 tests total. If any fail, correct `pg_back_scope.dart` rather than the test.

- [ ] **Step 3: Verify green and commit**

Run: `flutter analyze`
Expected: No issues found

```bash
git add test/core/pg_back_scope_test.dart
git commit -m "test: pin PgBackScope guard behaviour and precedence"
```

---

### Task 4: Shell — tab → Home → confirmed exit

**Files:**
- Modify: `lib/features/home/home_shell.dart`
- Create: `test/features/home_shell_back_test.dart`

**Interfaces:**
- Consumes: `PgExitConfirm` from Task 1.
- Produces: `HomeShell` handling system back for all five tabs. Branch index 0 is Home (see `PgBottomNav._items`: Home, Discover, Services, Community, Profile).

- [ ] **Step 1: Write the failing test**

Create `test/features/home_shell_back_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

void main() {
  setUp(PgExitConfirm.reset);

  testWidgets('back on a non-Home tab returns to Home', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        initialLocation: Routes.profile);
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.text('Home'), findsWidgets); // the Home tab is selected
    expect(find.text('Press back again to exit'), findsNothing);
  });

  testWidgets('first back on Home shows the toast and does not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        initialLocation: Routes.home);
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('second back on Home inside the window requests an exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        initialLocation: Routes.home);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        calls.add(c);
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);
    await _systemBack(t);

    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isTrue);
  });
}
```

Add these imports at the top of the file:

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/home_shell_back_test.dart`
Expected: FAIL — back currently falls through to the default handler, so no toast appears and the Profile tab does not return to Home.

- [ ] **Step 3: Rewrite `HomeShell`**

Replace `lib/features/home/home_shell.dart` with:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/home_shell_back_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/features/home/home_shell.dart test/features/home_shell_back_test.dart
git commit -m "feat: tab back returns to Home; Home needs a confirmed exit"
```

---

### Task 5: Terminal confirmation screens

The five screens where a plain pop walks back into a completed checkout.

**Files:**
- Modify: `lib/features/community/post_live_screen.dart`
- Modify: `lib/features/services/booking_confirmed_screen.dart`
- Modify: `lib/features/homestay/host_accepted_screen.dart`
- Modify: `lib/features/discovery/woof_match_screen.dart`
- Modify: `lib/features/payments/receipt_screen.dart`
- Modify: `lib/features/community/thread_screen.dart`
- Create: `test/features/back_terminal_screens_test.dart`

**Interfaces:**
- Consumes: `PgBackScope` from Task 2.

| Screen | `upTo` |
|---|---|
| `post_live_screen.dart` | `Routes.community` |
| `booking_confirmed_screen.dart` | `Routes.bookings` |
| `host_accepted_screen.dart` | `Routes.bookings` |
| `woof_match_screen.dart` | `Routes.discover` |
| `receipt_screen.dart` | `Routes.payments` |
| `thread_screen.dart` | `Routes.community` *(empty-stack fallback only — it pops normally when pushed from the feed)* |

- [ ] **Step 1: Write the failing test**

Create `test/features/back_terminal_screens_test.dart`:

Every one of these six screens takes a single **optional** payload (`const PostLiveScreen({super.key, this.post})` and so on), so each builds with no arguments — enough to read the intent it declares.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/navigation/pg_back_scope.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/features/community/post_live_screen.dart';
import 'package:pet_aggregator_app/features/community/thread_screen.dart';
import 'package:pet_aggregator_app/features/discovery/woof_match_screen.dart';
import 'package:pet_aggregator_app/features/homestay/host_accepted_screen.dart';
import 'package:pet_aggregator_app/features/payments/receipt_screen.dart';
import 'package:pet_aggregator_app/features/services/booking_confirmed_screen.dart';

typedef _Case = ({String name, Widget screen, String upTo});

/// A terminal screen that forgets its `upTo` silently regains the "back walks
/// into a finished checkout" bug. Nothing else in the suite would catch it.
const _cases = <_Case>[
  (name: 'PostLive',         screen: PostLiveScreen(),         upTo: Routes.community),
  (name: 'BookingConfirmed', screen: BookingConfirmedScreen(), upTo: Routes.bookings),
  (name: 'HostAccepted',     screen: HostAcceptedScreen(),     upTo: Routes.bookings),
  (name: 'WoofMatch',        screen: WoofMatchScreen(),        upTo: Routes.discover),
  (name: 'Receipt',          screen: ReceiptScreen(),          upTo: Routes.payments),
  (name: 'Thread',           screen: ThreadScreen(),           upTo: Routes.community),
];

void main() {
  for (final c in _cases) {
    testWidgets('${c.name} declares upTo ${c.upTo}', (t) async {
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(home: c.screen),
      ));
      await t.pump();

      final scope = t.widget<PgBackScope>(find.byType(PgBackScope).first);
      expect(scope.upTo, c.upTo, reason: '${c.name} must declare its up target');
    });
  }

  // The highest-stakes case end to end: after paying, back must reach My
  // Bookings and never re-enter the checkout that produced it.
  testWidgets('BookingConfirmed back reaches My Bookings, not the payment screen',
      (t) async {
    final router = GoRouter(initialLocation: '/pay', routes: [
      GoRoute(path: '/pay', builder: (_, _) => const Scaffold(body: Text('PAYMENT'))),
      GoRoute(
          path: Routes.bookingConfirmed,
          builder: (_, _) => const BookingConfirmedScreen()),
      GoRoute(path: Routes.bookings, builder: (_, _) => const Scaffold(body: Text('MY BOOKINGS'))),
    ]);

    await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await t.pumpAndSettle();

    router.push(Routes.bookingConfirmed);
    await t.pumpAndSettle();

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    expect(find.text('MY BOOKINGS'), findsOneWidget);
    expect(find.text('PAYMENT'), findsNothing);
  });
}
```

**If a screen throws while building with a null payload**, add the provider overrides it needs — `test/features/booking_confirmed_screen_test.dart` and `test/features/host_accepted_screen_test.dart` already construct these screens and show exactly which overrides each requires. Add overrides; do not weaken the assertion.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/back_terminal_screens_test.dart`
Expected: FAIL — no `PgBackScope` exists in any of the six screens yet.

- [ ] **Step 3: Wrap each screen**

In each of the six files, wrap the widget returned by `build` with `PgBackScope` and add the import:

```dart
import '../../core/navigation/pg_back_scope.dart';
```

For example, in `post_live_screen.dart`:

```dart
  @override
  Widget build(BuildContext context) {
    return PgBackScope(
      upTo: Routes.community,
      child: Scaffold(
        // ...existing body unchanged...
      ),
    );
  }
```

Do the same for the other five using the `upTo` from the table above. Change nothing else in these files.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/back_terminal_screens_test.dart`
Expected: PASS

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/features test/features/back_terminal_screens_test.dart
git commit -m "feat: terminal screens declare an up target instead of popping into a finished flow"
```

---

### Task 6: Auth funnel

The flow with the most stranding risk.

**Files:**
- Modify: `lib/features/auth/verify_email_screen.dart`
- Modify: `lib/features/auth/location_screen.dart`
- Modify: `lib/features/auth/signup_screen.dart`
- Modify: `lib/features/auth/welcome_screen.dart`
- Modify: `lib/features/onboarding/onboarding_screen.dart`
- Create: `test/features/back_auth_funnel_test.dart`

**Interfaces:**
- Consumes: `PgBackScope`, `authRepositoryProvider` (`signOut()`).

| Screen | Behaviour | How |
|---|---|---|
| `verify_email` | Signs out, → Welcome | `confirmWhen` is not right here; use a custom handler — see Step 3 |
| `location` | Confirmed exit | `PgBackScope(confirmExit: true, ...)` |
| `signup` | → Welcome | `PgBackScope(upTo: Routes.welcome, ...)` |
| `welcome` | Exits | No `upTo`, no stack → the resolver's final `SystemNavigator.pop()`. Wrap with a bare `PgBackScope` so the behaviour is explicit rather than incidental. |
| `onboarding` | Page 4→1, then exit | `PgBackScope(confirmExit: true)` **plus** an internal page-back — see Step 3 |

- [ ] **Step 1: Write the failing test**

Create `test/features/back_auth_funnel_test.dart` with these cases:

```dart
  testWidgets('verify-email back signs out and reaches Welcome', (t) async {
    // Sign up an UNVERIFIED user, land on verify-email, fire system back.
    // Assert: auth.currentUser is null AND the Welcome screen is showing.
    // A plain pop would bounce back here via the router redirect — that loop
    // is the bug this fixes.
  });

  testWidgets('signup back reaches Welcome', (t) async { /* ... */ });

  testWidgets('location back shows the exit confirmation, does not navigate',
      (t) async {
    // Assert the toast appears and we are STILL on the location screen —
    // popping to signup would be a dead end (the account already exists and
    // is verified by this point).
  });

  testWidgets('onboarding back steps to the previous page before exiting',
      (t) async { /* ... */ });
```

Write each body using `pumpPgApp` with `initialLocation` set to the screen under test and `authRepositoryProvider` overridden with a `FakeAuthRepository` in the right state (`FakeAuthRepository(emailVerified: false)` for verify-email). Read `test/features/email_verification_test.dart` first — it already sets up an unverified user and is the closest existing pattern.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/back_auth_funnel_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement each screen**

`verify_email_screen.dart` — back must sign out, so it needs a custom action rather than a declarative `upTo`. Wrap with a bare `PgBackScope(upTo: Routes.welcome, ...)` and add a `PopScope`-free sign-out in the same handler by giving the screen its own wrapper:

```dart
  @override
  Widget build(BuildContext context) {
    return PgBackScope(
      // Sign out first: a pop returns to a gated route, the redirect bounces
      // the user straight back here, and they are stuck with no way out.
      upTo: Routes.welcome,
      confirmWhen: () => false,
      child: Scaffold(/* ...existing... */),
    );
  }
```

Then wire the sign-out by making the screen call `ref.read(authRepositoryProvider).signOut()` immediately before navigation. Implement this by giving `PgBackScope` an optional `onBeforeLeave` callback:

```dart
  /// Runs after any confirm and before navigating. Use for side effects that
  /// must happen on the way out, e.g. signing out.
  final Future<void> Function()? onBeforeLeave;
```

and awaiting it in `_resolve` immediately before the `confirmExit` / `upTo` / `pop` branches, guarding `context.mounted` after. Add a test in `test/core/pg_back_scope_test.dart` asserting `onBeforeLeave` runs exactly once and before navigation.

`location_screen.dart`: `PgBackScope(confirmExit: true, child: ...)`.

`signup_screen.dart`: `PgBackScope(upTo: Routes.welcome, child: ...)`.

`welcome_screen.dart`: `PgBackScope(child: ...)` — explicit, no options.

`onboarding_screen.dart`: the screen already tracks a page index for `PgPageDots`. Use:

```dart
    return PgBackScope(
      confirmExit: true,
      onBeforeLeave: () async {
        // Handled by the page controller below; nothing to do here.
      },
      child: ...,
    );
```

and intercept earlier: if `_page > 0`, animate to `_page - 1` and do **not** delegate to `PgBackScope`. The simplest correct shape is a `blockWhen` that also performs the page-back:

```dart
      blockWhen: () {
        if (_page > 0) {
          _controller.previousPage(
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          return true; // consumed — do not exit
        }
        return false;
      },
      blockMessage: '', // never shown; the page moved instead
```

Suppress the snack when `blockMessage` is empty — add that guard to `_resolve` (`if (blockMessage.isNotEmpty) showPgSnack(...)`) and a test for it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/back_auth_funnel_test.dart test/core/pg_back_scope_test.dart`
Expected: PASS

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/core/navigation/pg_back_scope.dart lib/features/auth lib/features/onboarding test/features/back_auth_funnel_test.dart test/core/pg_back_scope_test.dart
git commit -m "feat: auth funnel back - verify-email signs out, location confirms exit"
```

---

### Task 7: Guarded forms

**Files:**
- Modify: `lib/features/pets/create_pet_screen.dart`
- Modify: `lib/features/services/pro_setup_screen.dart`
- Modify: `lib/features/homestay/host_setup_screen.dart`
- Modify: `lib/features/community/new_post_screen.dart`
- Create: `test/features/back_guarded_forms_test.dart`

**Interfaces:**
- Consumes: `PgBackScope.confirmWhen`.

Each screen's dirty check is a closure over state it already has. `create_pet_screen.dart` has `_name`, `_breed`, `_age` (`TextEditingController`) and `_photos` (`List<String>`); read the other three files for their equivalents before writing the predicate.

- [ ] **Step 1: Write the failing test**

Create `test/features/back_guarded_forms_test.dart`:

```dart
  testWidgets('create-pet back pops silently when nothing was entered', (t) async {
    // Land on create-pet, fire system back immediately.
    // Assert: no AlertDialog, and we left the screen.
  });

  testWidgets('create-pet back warns once a name is typed', (t) async {
    // Enter text into the name field, fire system back.
    // Assert: AlertDialog appears. Tap "Keep editing" -> still on create-pet
    // with the typed text intact.
  });

  testWidgets('create-pet back warns once a photo is attached', (t) async {
    // The expensive case: 3-5 uploaded photos are the most costly accidental
    // loss in the app.
  });
```

Write the same three cases for `pro_setup`, `host_setup` and `new_post`. Read `test/features/create_pet_screen_test.dart`, `test/features/host_setup_screen_test.dart` and `test/features/new_post_screen_test.dart` first — they already build these screens with the fakes and image-picker overrides you need.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/back_guarded_forms_test.dart`
Expected: FAIL — no dialog appears; back pops immediately.

- [ ] **Step 3: Wrap each form**

For `create_pet_screen.dart`:

```dart
  @override
  Widget build(BuildContext context) {
    return PgBackScope(
      // Only where leaving destroys real work. Photos are the expensive case:
      // three to five uploads gone on a stray back press.
      confirmWhen: () =>
          _photos.isNotEmpty ||
          _name.text.trim().isNotEmpty ||
          _breed.text.trim().isNotEmpty ||
          _age.text.trim().isNotEmpty,
      confirmMessage: "This pet isn't saved yet. Leaving now discards it.",
      child: Scaffold(/* ...existing... */),
    );
  }
```

Do the equivalent for the other three, using each screen's own controllers and photo lists, with a message naming what is lost ("This listing isn't saved yet…", "This post isn't published yet…").

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/back_guarded_forms_test.dart`
Expected: PASS

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/features test/features/back_guarded_forms_test.dart
git commit -m "feat: warn before discarding unsaved pet, listing and post work"
```

---

### Task 8: Payment screens

**Files:**
- Modify: `lib/features/services/payment_screen.dart`
- Modify: `lib/features/homestay/homestay_payment_screen.dart`
- Create: `test/features/back_payment_block_test.dart`

**Interfaces:**
- Consumes: `PgBackScope.blockWhen`. Both screens already expose `bool get _busy => _phase != _PayPhase.idle` over `enum _PayPhase { idle, opening, verifying }`. Use `_busy` — do not add new state.

- [ ] **Step 1: Write the failing test**

Create `test/features/back_payment_block_test.dart`:

```dart
  testWidgets('payment back is allowed before checkout starts', (t) async {
    // Land on the payment screen (phase idle), fire system back.
    // Assert: we left the screen.
  });

  testWidgets('payment back is refused while verifying', (t) async {
    // Drive the screen into the verifying phase via FakePaymentService, then
    // fire system back. Assert: still on the payment screen AND the
    // "Payment in progress" message is shown.
    // Backing out mid-verification is how money moves with no booking written.
  });
```

Read `test/features/homestay_payment_test.dart` first — it already drives `FakePaymentService` through the payment phases and is the pattern to copy.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/back_payment_block_test.dart`
Expected: FAIL — back is currently unguarded during verification.

- [ ] **Step 3: Wrap both screens**

```dart
  @override
  Widget build(BuildContext context) {
    return PgBackScope(
      // Backing out mid-verification is how a payment succeeds with no booking
      // written. The server owns the paid-write, but the user must not leave
      // before it lands.
      blockWhen: () => _busy,
      blockMessage: 'Payment in progress — please wait.',
      child: Scaffold(/* ...existing... */),
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/back_payment_block_test.dart`
Expected: PASS

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/features/services/payment_screen.dart lib/features/homestay/homestay_payment_screen.dart test/features/back_payment_block_test.dart
git commit -m "feat: refuse back while a payment is verifying"
```

---

### Task 9: `go` → `push` conversions

Only three. **Do not convert any others** — the four `go`-to-detail calls left alone are flow completions, and converting them re-creates the "back re-enters a finished checkout" bug this slice exists to fix.

**Files:**
- Modify: `lib/features/discovery/discover_screen.dart:73`
- Modify: `lib/features/home/home_screen.dart:97`
- Modify: `lib/features/services/services_list_screen.dart:53`
- Create: `test/features/back_push_conversions_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/back_push_conversions_test.dart`:

```dart
  testWidgets('back from the map returns to Discover', (t) async {
    // Tap the map affordance on Discover, then fire system back.
    // Assert: Discover is showing again.
  });

  testWidgets('back from the map returns to Home', (t) async { /* same, from Home */ });

  testWidgets('back from pro-setup returns to Services', (t) async { /* ... */ });
```

Read `test/features/nearby_map_screen_test.dart` for the map's provider overrides (it needs a Google Maps stub) and `test/features/home_screen_test.dart` for the Home fixture.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/back_push_conversions_test.dart`
Expected: FAIL — `context.go` replaced the stack, so back exits or lands elsewhere.

- [ ] **Step 3: Convert the three call sites**

```dart
// lib/features/discovery/discover_screen.dart:73
onTap: () => context.push(Routes.nearby),

// lib/features/home/home_screen.dart:97
onTap: () => context.push(Routes.nearby),

// lib/features/services/services_list_screen.dart:53
onTap: () => context.push(Routes.proSetup),
```

Change nothing else. In particular, leave these exactly as they are:
- `new_post_screen.dart:77` → `go(Routes.postLive)`
- `payment_screen.dart:55` → `go(Routes.bookingConfirmed)`
- `homestay_request_screen.dart:76` → `go(Routes.hostAccepted)`
- `post_live_screen.dart:44` → `go(Routes.thread)`
- all 15 `context.go(Routes.home)` calls

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/back_push_conversions_test.dart`
Expected: PASS

- [ ] **Step 5: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/features test/features/back_push_conversions_test.dart
git commit -m "fix: push (not go) when navigating deeper, so back works"
```

---

### Task 10: On-screen affordances — consolidate and complete

**Files:**
- Modify: the 8 screens with hand-rolled chevrons (find them with the command in Step 1)
- Modify: `lib/features/auth/signup_screen.dart`, `lib/features/services/pro_setup_screen.dart` (add an affordance)
- Create: `test/features/back_affordance_parity_test.dart`

**Interfaces:**
- Consumes: `PgAppBar({required String title, VoidCallback? onBack})`, `PgBackScope.pop`.

`post_live`, `booking_confirmed` and `host_accepted` are terminal celebration screens; they get their back from the hardware gesture and their existing primary CTA, **not** a chevron. Do not add one — it would clutter a deliberately clean confirmation. `location` gets none by design.

- [ ] **Step 1: Find the hand-rolled chevrons**

Run: `grep -rln "Icons.chevron_left" lib/features --include=*.dart`
Expected: 8 files. For each, the markup is an identical 42×42 `Container` with a border and `Icons.chevron_left` — the same thing `PgAppBar` already renders.

- [ ] **Step 2: Write the failing parity test**

Create `test/features/back_affordance_parity_test.dart`:

```dart
  testWidgets('the chevron and hardware back land in the same place', (t) async {
    // For a screen with a declared upTo (use ReceiptScreen -> Routes.payments):
    //   1. Pump it, tap the chevron, record where we land.
    //   2. Pump a fresh instance, fire system back, record where we land.
    //   3. Assert the two are identical.
    // This is the invariant the whole design rests on: today a chevron may
    // context.pop() while hardware back does something else entirely.
  });

  testWidgets('signup has a visible back affordance', (t) async {
    // Assert PgAppBar with a non-null onBack is present.
  });

  testWidgets('pro-setup has a visible back affordance', (t) async { /* ... */ });
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/back_affordance_parity_test.dart`
Expected: FAIL — signup and pro-setup have no affordance, and the hand-rolled chevrons call `context.pop()` directly rather than the shared resolver.

- [ ] **Step 4: Convert the chevrons and add the two missing**

In each of the 8 files, replace the hand-rolled chevron `Container`/`GestureDetector` with:

```dart
PgAppBar(title: '<the screen title already shown>',
         onBack: () => PgBackScope.pop(context)),
```

adding the imports:

```dart
import '../../core/widgets/pg_app_bar.dart';
import '../../core/navigation/pg_back_scope.dart';
```

Where a screen's header has extra trailing content (for example the Notifications screen's "Mark all read"), keep that content and only swap the chevron itself for `PgAppBar`'s — do not drop trailing actions.

Add `PgAppBar` with the same `onBack` to `signup_screen.dart` and `pro_setup_screen.dart`.

Also update the 16 screens already using `PgAppBar`: change any `onBack: () => context.pop()` to `onBack: () => PgBackScope.pop(context)` so every affordance runs the shared resolver.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/back_affordance_parity_test.dart`
Expected: PASS

- [ ] **Step 6: Verify green and commit**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

```bash
git add lib/features test/features/back_affordance_parity_test.dart
git commit -m "feat: one back affordance implementation, wired to the shared resolver"
```

---

### Task 11: Emulator verification

Widget tests cannot cover the real OS gesture, the predictive-back animation, or actual app termination — `SystemNavigator.pop()` can only ever be asserted as a call. The 2026-07-26 on-device pass found five defects invisible to widget tests.

**Files:**
- Modify: `left.md`

- [ ] **Step 1: Confirm the suite is green**

Run: `flutter analyze` — Expected: No issues found
Run: `flutter test` — Expected: all pass

- [ ] **Step 2: Launch on the emulator**

Run: `flutter devices` to find the running emulator, then:

Run: `flutter run -d emulator-5554`

If no emulator is running, start one from Android Studio's Device Manager first. Do **not** run `flutter build apk --release` — a debug run is what is wanted here.

- [ ] **Step 3: Walk the checklist**

Verify each and record the result:

| # | Check | Expected |
|---|---|---|
| 1 | Back on Discover, Services, Community, Profile | Returns to Home; app still running |
| 2 | Back on Home, once | "Press back again to exit" toast; app still running |
| 3 | Back on Home twice, quickly | App closes |
| 4 | Back on Home, pause 3s, back again | Toast again; app still running |
| 5 | Open a pet form, attach a photo, press back | Confirm dialog; "Keep editing" keeps the photo |
| 6 | Start a Razorpay payment, press back while verifying | Refused, "Payment in progress" toast |
| 7 | Complete a booking, press back on the confirmation | Lands on My Bookings, **not** back in checkout |
| 8 | Sign up, reach verify-email, press back | Signed out, on Welcome, no bounce |
| 9 | On the location step, press back | Exit confirmation, not a dead end |
| 10 | Edge-swipe back vs the button on the same screen | Identical result |
| 11 | Any plain screen | Predictive-back animation still plays |

- [ ] **Step 4: Record the results**

Append a short "Back navigation — on-device pass" section to `left.md` under the QA notes: the date, the device/emulator, which checks passed, and any defect found with its severity. Report defects honestly — a failed check is the point of running this.

- [ ] **Step 5: Commit**

```bash
git add left.md
git commit -m "docs: record the back-navigation on-device pass"
```

If any check failed, fix it with a test first, then re-run the checklist before committing.
