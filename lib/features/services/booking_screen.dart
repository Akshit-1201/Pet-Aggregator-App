import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/availability.dart';
import '../../data/models/booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/providers.dart';

/// How far ahead a customer can book.
const bookingWindowDays = 14;
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class BookingScreen extends ConsumerStatefulWidget {
  final Pro? pro;
  const BookingScreen({super.key, this.pro});
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  int _dateIndex = 0;

  /// The chosen slot's start (minutes after midnight); null until picked.
  /// Replaces a fixed list of three times that ignored the pro's hours and
  /// every other booking.
  int? _startMin;
  String? _petId;
  bool _starting = false;

  List<DateTime> get _days {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(bookingWindowDays, (i) => today.add(Duration(days: i)));
  }

  String _label(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  Future<void> _continue(Pro pro, List<PetProfile> pets) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    final start = _startMin;
    if (me == null || _starting || start == null) return;
    final pet = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    final fee = Booking.feeFor(pro.rate);
    final day = _days[_dateIndex];
    final draft = Booking(
        parentId: me.uid, proId: pro.uid, proName: pro.name, petId: pet.id, petName: pet.name,
        serviceType: pro.serviceType, rate: pro.rate, fee: fee, total: pro.rate + fee,
        dateLabel: _label(day), timeSlot: formatMinutes(start),
        startMin: start, durationMin: pro.availability.slotMinutes,
        date: Booking.isoDate(day), status: 'pending');
    setState(() => _starting = true);
    final repo = ref.read(bookingRepositoryProvider);
    try {
      final created = await repo.createBooking(draft);
      // Hold the time now, so a clash is caught here on the picker rather than
      // after paying. Only a real clash stops the booking: the server re-holds
      // when the payment order is created, so any other failure here (an
      // offline blip, an older backend) is safe to continue past.
      try {
        await repo.holdSlot(created.id);
      } on SlotTakenException {
        await repo.cancelBooking(created.id).catchError((_) {});
        if (!mounted) return;
        setState(() {
          _starting = false;
          _startMin = null;
        });
        showPgSnack(context, 'Someone just booked ${formatMinutes(start)}. Please pick another time.');
        return;
      } catch (e) {
        debugPrint('holdSlot failed, continuing to payment: $e');
      }
      if (!mounted) return;
      setState(() => _starting = false);
      context.push(Routes.payment, extra: created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      showPgSnack(context, "Couldn't start this booking — try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final pro = widget.pro;
    if (pro == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No pro selected')));
    }
    final pets = ref.watch(myPetsProvider).value ?? const <PetProfile>[];
    if (pets.isNotEmpty && (_petId == null || !pets.any((p) => p.id == _petId))) {
      _petId = pets.first.id;
    }
    final fee = Booking.feeFor(pro.rate);
    final total = pro.rate + fee;
    final days = _days;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Book a ${pro.serviceType.label}', onBack: () => PgBackScope.pop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Text('Select date', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                SizedBox(
                  height: 78,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: days.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 9),
                    itemBuilder: (_, i) {
                      final d = days[i];
                      final sel = _dateIndex == i;
                      final off = pro.availability.rangesFor(d.weekday).isEmpty;
                      return GestureDetector(
                        key: Key('booking-day-$i'),
                        onTap: () => setState(() {
                          _dateIndex = i;
                          _startMin = null; // a time picked on another day means nothing here
                        }),
                        child: Container(
                          width: 62,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sel ? c.brand : c.surface,
                            border: sel ? null : Border.all(color: c.border),
                            borderRadius: BorderRadius.circular(15)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(_weekdays[d.weekday - 1].toUpperCase(),
                              style: PgText.inter(11, FontWeight.w600,
                                color: sel ? Colors.white70 : c.faint)),
                            const SizedBox(height: 3),
                            Text('${d.day}',
                              style: PgText.poppins(17, FontWeight.w800,
                                color: sel ? Colors.white : (off ? c.faint : c.text))),
                            Text(off ? 'Off' : _months[d.month - 1],
                              style: PgText.inter(10.5, FontWeight.w500,
                                color: sel ? Colors.white70 : c.faint)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Select time', style: PgText.sectionHeader(context)),
                  Text('${pro.availability.slotMinutes} min ${pro.unit}',
                    style: PgText.inter(12.5, FontWeight.w600, color: c.muted)),
                ]),
                const SizedBox(height: 11),
                _SlotPicker(
                  pro: pro,
                  day: days[_dateIndex],
                  selected: _startMin,
                  onSelect: (m) => setState(() => _startMin = m),
                  onSelectionLost: () {
                    if (mounted) setState(() => _startMin = null);
                  },
                ),
                const SizedBox(height: 20),
                Text('For', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                if (pets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(15)),
                    child: Text('Add a pet to book', style: PgText.inter(14, FontWeight.w600, color: c.muted)))
                else
                  Column(children: [
                    for (final p in pets) ...[
                      GestureDetector(
                        onTap: () => setState(() => _petId = p.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.surface,
                            border: Border.all(color: _petId == p.id ? c.brand : c.border,
                              width: _petId == p.id ? 2 : 1),
                            borderRadius: BorderRadius.circular(15)),
                          child: Row(children: [
                            PgImageSlot(size: 44, circle: true, imageUrl: p.photoUrl),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.displayName, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                              Text(PetProfile.detailLine([p.breed, p.ageLabel]),
                                style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                            ])),
                            if (_petId == p.id) Icon(Icons.check_circle, color: c.brand, size: 22),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    _priceRow('${pro.serviceType.label} (${pro.unit})', '₹${pro.rate}', c),
                    const SizedBox(height: 9),
                    _priceRow('Pawgo service fee', '₹$fee', c),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Container(height: 1, color: c.border)),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Total', style: PgText.poppins(15, FontWeight.w700, color: c.text)),
                      Text('₹$total', style: PgText.poppins(15, FontWeight.w800, color: c.brand)),
                    ]),
                  ]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: pets.isEmpty
                ? PgPrimaryButton(
                    label: 'Add a pet', onPressed: () => context.push(Routes.createPet))
                : PgPrimaryButton(
                    label: _starting
                        ? 'Starting…'
                        : _startMin == null ? 'Pick a time to continue' : 'Continue to payment',
                    onPressed: (_starting || _startMin == null) ? () {} : () => _continue(pro, pets)),
          ),
        ]),
      ),
    );
  }

  Widget _priceRow(String label, String value, PgColors c) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
        Text(value, style: PgText.inter(13.5, FontWeight.w600, color: c.text)),
      ]);
}

/// One day's time grid: the pro's slots, with times someone else already has
/// shown struck through rather than silently missing — "booked" is useful
/// information, an unexplained gap is not.
class _SlotPicker extends ConsumerWidget {
  final Pro pro;
  final DateTime day;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onSelectionLost;
  const _SlotPicker({required this.pro, required this.day, required this.selected,
      required this.onSelect, required this.onSelectionLost});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    Widget note(String text) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(15)),
          child: Text(text, style: PgText.inter(13.5, FontWeight.w500, color: c.muted)));

    final first = pro.name.trim().split(' ').first;
    if (pro.availability.rangesFor(day.weekday).isEmpty) {
      return note("$first doesn't take bookings on this day. Try another date.");
    }
    final busyAsync = ref.watch(busySlotsProvider((pro.uid, Booking.isoDate(day))));
    if (!busyAsync.hasValue) {
      return busyAsync.hasError
          ? note("Couldn't load free times. Check your connection and try again.")
          : const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final slots = slotsForDay(
            availability: pro.availability, day: day, busy: busyAsync.value!, now: DateTime.now())
        .where((s) => s.state != SlotState.past)
        .toList();

    // The busy list is live: if someone else just took the picked time, drop
    // the selection rather than let Continue run into a guaranteed clash.
    if (selected != null && !slots.any((s) => s.startMin == selected && s.bookable)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onSelectionLost());
    }
    if (slots.isEmpty) return note('No more times today. Try another date.');
    if (!slots.any((s) => s.bookable)) {
      return note('$first is fully booked on this day. Try another date.');
    }

    return Wrap(spacing: 9, runSpacing: 9, children: [
      for (final s in slots)
        Semantics(
          button: s.bookable,
          label: s.bookable ? s.label : '${s.label}, already booked',
          child: GestureDetector(
            key: Key('slot-${s.startMin}'),
            onTap: s.bookable ? () => onSelect(s.startMin) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: selected == s.startMin ? c.brand : (s.bookable ? c.surface : c.surface2),
                border: selected == s.startMin ? null : Border.all(color: c.border),
                borderRadius: BorderRadius.circular(13)),
              child: Text(s.label,
                style: PgText.inter(13.5, FontWeight.w600,
                        color: selected == s.startMin ? Colors.white : (s.bookable ? c.text : c.faint))
                    .copyWith(decoration: s.bookable ? null : TextDecoration.lineThrough)),
            ),
          ),
        ),
    ]);
  }
}
