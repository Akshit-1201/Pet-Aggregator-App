import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/availability.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  final monday = DateTime(2026, 10, 12); // a Monday

  test('formatMinutes renders 12-hour times', () {
    expect(formatMinutes(0), '12:00 AM');
    expect(formatMinutes(540), '9:00 AM');
    expect(formatMinutes(720), '12:00 PM');
    expect(formatMinutes(1050), '5:30 PM');
  });

  test('slots fill each window at the slot length, never running past its end', () {
    const a = Availability(weekly: {1: [TimeRange(540, 690)]}, slotMinutes: 60);
    final s = slotsForDay(availability: a, day: monday, busy: const [], now: DateTime(2026, 1, 1));
    expect(s.map((x) => x.startMin), [540, 600]); // 11:00-12:00 would end past 11:30
  });

  test('busy intervals mark overlapping slots taken, touching ones free', () {
    const a = Availability(weekly: {1: [TimeRange(540, 720)]}, slotMinutes: 60);
    final s = slotsForDay(availability: a, day: monday, now: DateTime(2026, 1, 1),
        busy: const [BusySlot(bookingId: 'b', startMin: 570, durationMin: 30)]);
    expect({for (final x in s) x.startMin: x.state},
        {540: SlotState.taken, 600: SlotState.free, 660: SlotState.free});
  });

  test("today's slots inside the lead time are past", () {
    const a = Availability(weekly: {1: [TimeRange(540, 720)]}, slotMinutes: 60);
    final s = slotsForDay(availability: a, day: monday, busy: const [],
        now: DateTime(2026, 10, 12, 9, 30)); // 9:30 + 60 min lead → 10:30 cutoff
    expect({for (final x in s) x.startMin: x.state},
        {540: SlotState.past, 600: SlotState.past, 660: SlotState.free});
  });

  test('round-trips through Firestore maps', () {
    const a = Availability(weekly: {1: [TimeRange(540, 720)], 6: [TimeRange(600, 660)]},
        slotMinutes: 45);
    final back = Availability.fromMap(a.toMap());
    expect(back.slotMinutes, 45);
    expect(back.rangesFor(1), const [TimeRange(540, 720)]);
    expect(back.rangesFor(6), const [TimeRange(600, 660)]);
    expect(back.rangesFor(2), isEmpty);
  });

  test('listings saved before time slots get the defaults (matches the server)', () {
    final pro = Pro.fromMap('p', {'name': 'A', 'rate': 250});
    expect(pro.availability.slotMinutes, 60);
    for (var d = 1; d <= 7; d++) {
      expect(pro.availability.rangesFor(d), const [TimeRange(480, 1200)]);
    }
  });

  test('malformed data falls back instead of making the pro unbookable', () {
    final a = Availability.fromMap({'slotMinutes': 7, 'weekly': {'1': [{'start': 600, 'end': 500}]}});
    expect(a.slotMinutes, 60);
    expect(a.rangesFor(1), isEmpty);
  });

  test('busySlotsFrom keeps bookings and live holds, drops lapsed holds', () {
    final busy = busySlotsFrom({
      'slots': {
        'a': {'startMin': 540, 'durationMin': 60, 'status': 'booked', 'heldUntil': 0},
        'b': {'startMin': 600, 'durationMin': 60, 'status': 'held', 'heldUntil': 2000},
        'c': {'startMin': 660, 'durationMin': 60, 'status': 'held', 'heldUntil': 500},
      },
    }, nowMs: 1000);
    expect(busy.map((b) => b.bookingId).toSet(), {'a', 'b'});
  });
}
