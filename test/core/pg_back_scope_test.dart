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
    final scope = t.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).last);
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
          upTo: '/parent', child: Scaffold(body: Text('DETAIL'))),
    );
    await _pump(t, r);
    r.push('/detail');
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);

    await _systemBack(t);
    // Not back to ROOT — upTo forced the destination.
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
    final scope = t.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).last);
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
