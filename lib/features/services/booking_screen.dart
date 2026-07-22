import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';
import '../../data/repositories/providers.dart';

const _times = ['8:00 AM', '5:00 PM', '6:30 PM'];
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
  int _timeIndex = 1;
  String? _petId;

  List<DateTime> get _days => List.generate(4, (i) => DateTime.now().add(Duration(days: i)));
  String _label(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  bool _starting = false;

  Future<void> _continue(Pro pro, List<PetProfile> pets) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null || _starting) return;
    final pet = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    final fee = Booking.feeFor(pro.rate);
    final day = _days[_dateIndex];
    final draft = Booking(
        parentId: me.uid, proId: pro.uid, proName: pro.name, petId: pet.id, petName: pet.name,
        serviceType: pro.serviceType, rate: pro.rate, fee: fee, total: pro.rate + fee,
        dateLabel: _label(day), timeSlot: _times[_timeIndex],
        date: Booking.isoDate(day), status: 'pending');
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await ref.read(bookingRepositoryProvider).createBooking(draft);
      if (!mounted) return;
      setState(() => _starting = false);
      context.push(Routes.payment, extra: created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn\'t start this booking — try again.')));
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

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Book a ${pro.serviceType.label}', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Text('Select date', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                Row(children: [
                  for (var i = 0; i < _days.length; i++) ...[
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _dateIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _dateIndex == i ? c.brand : c.surface,
                          border: _dateIndex == i ? null : Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(15)),
                        child: Column(children: [
                          Text(_weekdays[_days[i].weekday - 1].toUpperCase(),
                            style: PgText.inter(11, FontWeight.w600,
                              color: _dateIndex == i ? Colors.white70 : c.faint)),
                          const SizedBox(height: 3),
                          Text('${_days[i].day}',
                            style: PgText.poppins(17, FontWeight.w800,
                              color: _dateIndex == i ? Colors.white : c.text)),
                        ]),
                      ),
                    )),
                    if (i != _days.length - 1) const SizedBox(width: 9),
                  ],
                ]),
                const SizedBox(height: 20),
                Text('Select time', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (var i = 0; i < _times.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _timeIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                        decoration: BoxDecoration(
                          color: _timeIndex == i ? c.brand : c.surface,
                          border: _timeIndex == i ? null : Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text(_times[i], style: PgText.inter(13.5, FontWeight.w600,
                          color: _timeIndex == i ? Colors.white : c.text)),
                      ),
                    ),
                ]),
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
                            const PgImageSlot(size: 44, circle: true),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                              Text('${p.breed} · ${p.ageLabel}',
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
                    label: _starting ? 'Starting…' : 'Continue to payment',
                    onPressed: (pets.isEmpty || _starting) ? () {} : () => _continue(pro, pets)),
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
