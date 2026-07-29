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
