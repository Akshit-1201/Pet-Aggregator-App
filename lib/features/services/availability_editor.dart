import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/availability.dart';

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// A pro's weekly hours: which days they work, from when to when, and how
/// long one booking lasts. This is what the customer's slot picker is built
/// from, so it is the pro's control over when they can be booked.
///
/// One window per day keeps it a two-tap edit; that covers how walkers,
/// sitters and groomers actually describe their hours.
class AvailabilityEditor extends StatelessWidget {
  final Availability value;
  final ValueChanged<Availability> onChanged;
  const AvailabilityEditor({super.key, required this.value, required this.onChanged});

  /// Why [value] can't be saved, or null if it can.
  static String? validate(Availability a) {
    final open = [for (var d = 1; d <= 7; d++) ...a.rangesFor(d)];
    if (open.isEmpty) return 'Turn on at least one day so parents can book you.';
    for (var d = 1; d <= 7; d++) {
      for (final r in a.rangesFor(d)) {
        if (r.end - r.start < a.slotMinutes) {
          return '${_dayNames[d - 1]}: hours must fit at least one ${a.slotMinutes}-minute booking.';
        }
      }
    }
    return null;
  }

  void _setDay(int day, TimeRange? range) {
    final weekly = {for (var d = 1; d <= 7; d++) d: value.rangesFor(d)};
    weekly[day] = range == null ? const [] : [range];
    onChanged(value.copyWith(weekly: weekly));
  }

  Future<void> _pickTime(BuildContext context, int day, TimeRange r, {required bool start}) async {
    final current = start ? r.start : r.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
      helpText: start ? 'Start of your day' : 'End of your day',
    );
    if (picked == null) return;
    var m = picked.hour * 60 + picked.minute;
    if (!start && m == 0) m = 1440; // "12:00 AM" as an end means midnight
    _setDay(day, start ? TimeRange(m, r.end) : TimeRange(r.start, m));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    Widget timeChip(String key, String label, VoidCallback onTap) => GestureDetector(
          key: Key(key),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: PgText.inter(13, FontWeight.w600, color: c.text))),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Each booking lasts', style: PgText.label(context)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in Availability.allowedSlotMinutes)
          GestureDetector(
            key: Key('slot-length-$m'),
            onTap: () => onChanged(value.copyWith(slotMinutes: m)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: value.slotMinutes == m ? c.brandSoft : c.surface,
                border: Border.all(color: value.slotMinutes == m ? c.brand : c.border,
                    width: value.slotMinutes == m ? 2 : 1),
                borderRadius: BorderRadius.circular(12)),
              child: Text(m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} hr' : '${m ~/ 60}h ${m % 60}m'),
                style: PgText.inter(13, FontWeight.w600,
                    color: value.slotMinutes == m ? c.brand : c.text)),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      Text('When can parents book you?', style: PgText.label(context)),
      const SizedBox(height: 4),
      Text('Times you\'re already booked are blocked automatically.',
          style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
      const SizedBox(height: 8),
      for (var d = 1; d <= 7; d++)
        Builder(builder: (context) {
          final ranges = value.rangesFor(d);
          final on = ranges.isNotEmpty;
          final r = on ? ranges.first : const TimeRange(540, 1080);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              SizedBox(width: 92,
                child: Text(_dayNames[d - 1],
                  style: PgText.inter(13.5, FontWeight.w600, color: on ? c.text : c.faint))),
              Expanded(
                child: on
                    ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                        timeChip('avail-$d-start', formatMinutes(r.start),
                            () => _pickTime(context, d, r, start: true)),
                        Text('–', style: PgText.inter(13, FontWeight.w500, color: c.muted)),
                        timeChip('avail-$d-end', formatMinutes(r.end),
                            () => _pickTime(context, d, r, start: false)),
                      ])
                    : Text('Not working', style: PgText.inter(13, FontWeight.w500, color: c.faint)),
              ),
              Switch(
                key: Key('avail-$d-toggle'),
                value: on,
                activeThumbColor: c.brand,
                onChanged: (v) => _setDay(d, v ? r : null),
              ),
            ]),
          );
        }),
    ]);
  }
}
