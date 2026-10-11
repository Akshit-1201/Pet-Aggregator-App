/// A pro's bookable hours, and the slot picker built from them.
///
/// Mirrors `functions/src/slots.ts` — the server re-validates every slot
/// against the same rules, so the two must agree (defaults included).
/// Times are minutes since midnight, Mumbai time; weekdays are ISO
/// (1 = Monday … 7 = Sunday), matching [DateTime.weekday].
library;

class TimeRange {
  final int start, end; // minutes since midnight; start < end
  const TimeRange(this.start, this.end);

  Map<String, dynamic> toMap() => {'start': start, 'end': end};

  @override
  bool operator ==(Object other) => other is TimeRange && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
}

class Availability {
  /// ISO weekday → open windows that day. A missing or empty list = closed.
  final Map<int, List<TimeRange>> weekly;
  final int slotMinutes;

  const Availability({required this.weekly, required this.slotMinutes});

  static const allowedSlotMinutes = [30, 45, 60, 90, 120];

  /// What a listing without saved hours gets — every day 8 AM–8 PM, hourly.
  /// Must equal DEFAULT_AVAILABILITY in functions/src/slots.ts.
  static const defaults = Availability(weekly: {
    1: [TimeRange(480, 1200)], 2: [TimeRange(480, 1200)], 3: [TimeRange(480, 1200)],
    4: [TimeRange(480, 1200)], 5: [TimeRange(480, 1200)], 6: [TimeRange(480, 1200)],
    7: [TimeRange(480, 1200)],
  }, slotMinutes: 60);

  List<TimeRange> rangesFor(int weekday) => weekly[weekday] ?? const [];

  Availability copyWith({Map<int, List<TimeRange>>? weekly, int? slotMinutes}) =>
      Availability(weekly: weekly ?? this.weekly, slotMinutes: slotMinutes ?? this.slotMinutes);

  Map<String, dynamic> toMap() => {
        'weekly': {
          for (var d = 1; d <= 7; d++)
            '$d': [for (final r in rangesFor(d)) r.toMap()],
        },
        'slotMinutes': slotMinutes,
      };

  /// Lenient on purpose: a malformed listing falls back rather than becoming
  /// unbookable (same as the server's parseAvailability).
  static Availability fromMap(Object? raw) {
    if (raw is! Map) return defaults;
    final slot = raw['slotMinutes'];
    final slotMinutes = (slot is int && allowedSlotMinutes.contains(slot)) ? slot : 60;
    final w = raw['weekly'];
    if (w is! Map) return Availability(weekly: defaults.weekly, slotMinutes: slotMinutes);
    final weekly = <int, List<TimeRange>>{};
    for (var d = 1; d <= 7; d++) {
      final list = w['$d'];
      weekly[d] = [
        if (list is List)
          for (final e in list)
            if (e is Map && e['start'] is int && e['end'] is int &&
                (e['start'] as int) >= 0 && (e['end'] as int) <= 1440 &&
                (e['start'] as int) < (e['end'] as int))
              TimeRange(e['start'] as int, e['end'] as int),
      ];
    }
    return Availability(weekly: weekly, slotMinutes: slotMinutes);
  }
}

/// An interval already taken on a pro's day — a confirmed booking or someone
/// else's live hold. Read from `proSchedule/{proId}_{date}`.
class BusySlot {
  final String bookingId;
  final int startMin, durationMin;
  const BusySlot({required this.bookingId, required this.startMin, required this.durationMin});

  bool overlaps(int start, int duration) =>
      start < startMin + durationMin && startMin < start + duration;
}

/// Parses a proSchedule doc's `slots` map, keeping only entries that still
/// block a time (booked, or a hold that hasn't lapsed).
List<BusySlot> busySlotsFrom(Map<String, dynamic>? data, {required int nowMs}) {
  final slots = data?['slots'];
  if (slots is! Map) return const [];
  return [
    for (final e in slots.entries)
      if (e.value is Map &&
          ((e.value as Map)['status'] == 'booked' ||
              (((e.value as Map)['heldUntil'] as num?) ?? 0) > nowMs))
        BusySlot(
          bookingId: e.key as String,
          startMin: ((e.value as Map)['startMin'] as num).toInt(),
          durationMin: ((e.value as Map)['durationMin'] as num).toInt(),
        ),
  ];
}

enum SlotState { free, taken, past }

class SlotOption {
  final int startMin, durationMin;
  final SlotState state;
  const SlotOption(this.startMin, this.durationMin, this.state);
  bool get bookable => state == SlotState.free;
  String get label => formatMinutes(startMin);
}

/// Every slot the pro offers on [day], marked free / taken / past.
///
/// Taken slots are returned (not dropped) so the picker can show them greyed
/// out — "booked" is information, an empty gap is a mystery. [leadMinutes]
/// stops someone booking a walk that starts in five minutes.
List<SlotOption> slotsForDay({
  required Availability availability,
  required DateTime day,
  required List<BusySlot> busy,
  required DateTime now,
  int leadMinutes = 60,
}) {
  final len = availability.slotMinutes;
  final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
  final cutoff = isToday ? now.hour * 60 + now.minute + leadMinutes : -1;
  final out = <SlotOption>[];
  final ranges = [...availability.rangesFor(day.weekday)]..sort((a, b) => a.start.compareTo(b.start));
  for (final r in ranges) {
    for (var s = r.start; s + len <= r.end; s += len) {
      final state = s < cutoff
          ? SlotState.past
          : busy.any((b) => b.overlaps(s, len))
              ? SlotState.taken
              : SlotState.free;
      out.add(SlotOption(s, len, state));
    }
  }
  return out;
}

/// 540 → "9:00 AM", 1050 → "5:30 PM".
String formatMinutes(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
}
