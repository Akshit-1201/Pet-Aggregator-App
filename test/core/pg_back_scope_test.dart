import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/navigation/pg_back_scope.dart';

/// A two-route app so we can test both "there is a stack" and "there is not".
GoRouter _router({
  required Widget Function() detail,
  String initial = '/detail',
}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('ROOT')),
    ),
    GoRoute(
      path: '/parent',
      builder: (_, _) => const Scaffold(body: Text('PARENT')),
    ),
    GoRoute(path: '/detail', builder: (_, _) => detail()),
  ],
);

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
    final r = _router(
      detail: () => const PgBackScope(child: Scaffold(body: Text('DETAIL'))),
    );
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();
    expect(find.text('PARENT'), findsOneWidget);

    await _systemBack(t);
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('canPop is true when nothing needs interception', (t) async {
    // As transcribed from the brief this started at '/detail' (the bottom of
    // the stack, nothing below it) and pushed '/parent' on top — but
    // `context.canPop()` is evaluated once, when DETAIL itself builds, so
    // starting DETAIL at the bottom bakes in canPop() == false regardless of
    // what's pushed above it afterward. Starting at '/' and pushing '/detail'
    // puts a real entry beneath DETAIL, so its own canPop() is true — what
    // this test is actually meant to exercise.
    final r = _router(
      initial: '/',
      detail: () => const PgBackScope(child: Scaffold(body: Text('DETAIL'))),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    // Predictive back depends on canPop being true rather than us intercepting.
    // `find.byType(PopScope)` does an exact Type match, which misses this
    // Flutter version's generic `PopScope<Object>` runtime type; a predicate
    // using `is` accounts for the type argument.
    final scope = t.widget<PopScope>(
      find.byWidgetPredicate((w) => w is PopScope).last,
    );
    expect(scope.canPop, isTrue);
  });

  testWidgets('upTo wins even when there IS a poppable stack', (t) async {
    // initial=/ then push /detail on top, so DETAIL sits on a real, poppable
    // stack (back could naturally land on ROOT) — as transcribed from the
    // brief this pushed '/' on top of an initial '/detail', which puts the
    // *unwrapped* ROOT screen on top instead of DETAIL, so nothing ever
    // reaches DETAIL's resolver on back and the assertion below cannot pass.
    // Swapping initial/push exercises what the test documents: a screen with
    // upTo set, on top of a poppable stack, still redirects instead of
    // popping naturally.
    final r = _router(
      initial: '/',
      detail: () => const PgBackScope(
        upTo: '/parent',
        child: Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);

    await _systemBack(t);
    // Not back to ROOT — upTo forced the destination.
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('upTo is used when there is NO stack (cold-start deep link)', (
    t,
  ) async {
    final r = _router(
      detail: () => const PgBackScope(
        upTo: '/parent',
        child: Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    expect(find.text('DETAIL'), findsOneWidget);

    await _systemBack(t);
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('canPop is false when upTo is set, so we intercept', (t) async {
    final r = _router(
      detail: () => const PgBackScope(
        upTo: '/parent',
        child: Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    final scope = t.widget<PopScope>(
      find.byWidgetPredicate((w) => w is PopScope).last,
    );
    expect(scope.canPop, isFalse);
  });

  // upToIfEmpty: unlike upTo, a real pop wins whenever a stack exists — it
  // only fires as a fallback for the empty-stack / cold-start case. This is
  // what lets a screen reached by `push` (thread, woof-match, receipt) return
  // to its live parent with state intact, instead of `go` rebuilding it.

  testWidgets('upToIfEmpty does NOT suppress a real pop: a poppable stack pops '
      'to the actual parent, not to upToIfEmpty', (t) async {
    final r = _router(
      initial: '/',
      detail: () => const PgBackScope(
        upToIfEmpty: '/parent',
        child: Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);

    await _systemBack(t);
    // The real stack pop wins: back lands on ROOT (the actual parent
    // beneath DETAIL), never on '/parent' — upToIfEmpty didn't fire because
    // there was something to pop to.
    expect(find.text('ROOT'), findsOneWidget);
    expect(find.text('PARENT'), findsNothing);
  });

  testWidgets(
    'upToIfEmpty is used when there is NO stack (cold-start deep link)',
    (t) async {
      final r = _router(
        detail: () => const PgBackScope(
          upToIfEmpty: '/parent',
          child: Scaffold(body: Text('DETAIL')),
        ),
      );
      await _pump(t, r);
      expect(find.text('DETAIL'), findsOneWidget);

      await _systemBack(t);
      expect(find.text('PARENT'), findsOneWidget);
    },
  );

  testWidgets('canPop is true when only upToIfEmpty is set and a stack exists '
      '(predictive back preserved)', (t) async {
    final r = _router(
      initial: '/',
      detail: () => const PgBackScope(
        upToIfEmpty: '/parent',
        child: Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    final scope = t.widget<PopScope>(
      find.byWidgetPredicate((w) => w is PopScope).last,
    );
    expect(scope.canPop, isTrue);
  });

  testWidgets('PgBackScope.pop runs the same resolver as system back', (
    t,
  ) async {
    late BuildContext inner;
    final r = _router(
      detail: () => PgBackScope(
        upTo: '/parent',
        child: Scaffold(
          body: Builder(
            builder: (c) {
              inner = c;
              return const Text('DETAIL');
            },
          ),
        ),
      ),
    );
    await _pump(t, r);

    await PgBackScope.pop(inner);
    await t.pumpAndSettle();
    expect(find.text('PARENT'), findsOneWidget);
  });

  testWidgets('PgBackScope.pop without a scope falls back to a plain pop', (
    t,
  ) async {
    late BuildContext inner;
    final r = _router(
      detail: () => Scaffold(
        body: Builder(
          builder: (c) {
            inner = c;
            return const Text('DETAIL');
          },
        ),
      ),
    );
    await _pump(t, r);
    r.push('/parent');
    await t.pumpAndSettle();

    await PgBackScope.pop(inner);
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);
  });

  // The five tests below all need DETAIL — the screen carrying the
  // PgBackScope under test — to be the *active* route when system back
  // fires, per the ordering gotcha documented above ("canPop is true when
  // nothing needs interception"): pushing an unwrapped '/parent' on top of
  // DETAIL just exercises PARENT's own (nonexistent) guard, popping it
  // trivially and never reaching DETAIL's resolver at all. So each starts at
  // '/parent' and pushes '/detail' on top instead, matching the fix already
  // applied to the 'upTo' tests above. That flips which screen remains
  // visible after a successful pop (PARENT, not DETAIL) — the assertions
  // below reflect that, while pinning the exact same guarantees the brief
  // named (dialog shown or not, which button does what, block beats confirm).

  testWidgets('confirmWhen false pops silently, no dialog', (t) async {
    final r = _router(
      initial: '/parent',
      detail: () => PgBackScope(
        confirmWhen: () => false,
        child: const Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('PARENT'), findsOneWidget); // popped silently
  });

  testWidgets('confirmWhen true shows a dialog; Keep editing stays put', (
    t,
  ) async {
    final r = _router(
      initial: '/parent',
      detail: () => PgBackScope(
        confirmWhen: () => true,
        child: const Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget); // never left
  });

  testWidgets('confirmWhen true then Discard leaves the screen', (t) async {
    final r = _router(
      initial: '/parent',
      detail: () => PgBackScope(
        confirmWhen: () => true,
        child: const Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    await _systemBack(t);

    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(find.text('PARENT'), findsOneWidget); // left the screen
  });

  testWidgets('blockWhen refuses back and shows the message', (t) async {
    final r = _router(
      initial: '/parent',
      detail: () => PgBackScope(
        blockWhen: () => true,
        blockMessage: 'Payment in progress',
        child: const Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.text('DETAIL'), findsOneWidget); // still here
    expect(find.text('Payment in progress'), findsOneWidget);
  });

  testWidgets('blocked wins over dirty — no dialog is shown', (t) async {
    final r = _router(
      initial: '/parent',
      detail: () => PgBackScope(
        blockWhen: () => true,
        confirmWhen: () => true,
        child: const Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('DETAIL'), findsOneWidget); // still here
  });

  testWidgets('a throwing predicate is treated as false, never traps', (
    t,
  ) async {
    final r = _router(
      initial: '/parent',
      detail: () => PgBackScope(
        blockWhen: () => throw StateError('boom'),
        child: const Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.text('PARENT'), findsOneWidget); // it popped
  });

  testWidgets('confirmExit shows the toast first, does not leave', (t) async {
    PgExitConfirm.reset();
    final r = _router(
      detail: () => const PgBackScope(
        confirmExit: true,
        child: Scaffold(body: Text('DETAIL')),
      ),
    );
    await _pump(t, r);

    await _systemBack(t);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('DETAIL'), findsOneWidget);
  });
}
