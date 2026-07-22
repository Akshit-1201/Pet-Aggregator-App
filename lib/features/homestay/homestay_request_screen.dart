import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/homestay.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';

class HomestayRequestScreen extends ConsumerStatefulWidget {
  final Homestay? homestay;
  const HomestayRequestScreen({super.key, this.homestay});
  @override
  ConsumerState<HomestayRequestScreen> createState() => _HomestayRequestScreenState();
}

class _HomestayRequestScreenState extends ConsumerState<HomestayRequestScreen> {
  late DateTime _checkIn;
  late DateTime _checkOut;
  String? _petId;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkIn = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _checkOut = _checkIn.add(const Duration(days: 3));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _nights => HomestayBooking.nightsBetween(_checkIn, _checkOut);

  Future<void> _pickDates() async {
    final today = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      initialDateRange: DateTimeRange(start: _checkIn, end: _checkOut),
    );
    if (range != null && range.duration.inDays >= 1) {
      setState(() {
        _checkIn = DateTime(range.start.year, range.start.month, range.start.day);
        _checkOut = DateTime(range.end.year, range.end.month, range.end.day);
      });
    }
  }

  Future<void> _send(Homestay h, List<PetProfile> pets) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    final pet = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    final nights = _nights;
    final subtotal = h.ratePerNight * nights;
    const fee = HomestayBooking.serviceFee;
    final draft = HomestayBooking(
      guestId: me.uid, hostId: h.uid, homeName: h.homeName, hostName: h.hostName,
      petId: pet.id, petName: pet.name, ratePerNight: h.ratePerNight,
      checkIn: _checkIn, checkOut: _checkOut, nights: nights,
      subtotal: subtotal, fee: fee, total: subtotal + fee, note: _note.text.trim());
    setState(() => _saving = true);
    await ref.read(homestayBookingRepositoryProvider).createHomestayBooking(draft);
    if (mounted) context.go(Routes.hostAccepted, extra: draft);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final h = widget.homestay;
    if (h == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No home selected')));
    }
    final pets = ref.watch(myPetsProvider).value ?? const <PetProfile>[];
    if (pets.isNotEmpty && (_petId == null || !pets.any((p) => p.id == _petId))) {
      _petId = pets.first.id;
    }
    final nights = _nights;
    final subtotal = h.ratePerNight * nights;
    const fee = HomestayBooking.serviceFee;
    final total = subtotal + fee;
    final hostFirst = h.hostName.split(' ').first;
    final nightWord = nights == 1 ? 'night' : 'nights';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Request booking', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const PgImageSlot(size: 52, radius: 14, emoji: '🏡'),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h.homeName, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                      Text('${h.area} · ${h.reviewCount == 0 ? 'New' : '★ ${h.rating.toStringAsFixed(1)}'}',
                        style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Dates', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                GestureDetector(
                  onTap: _pickDates,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(15)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 17, color: c.brand),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        '${HomestayBooking.fmtDay(_checkIn)} → ${HomestayBooking.fmtDay(_checkOut)}',
                        style: PgText.inter(13.5, FontWeight.w600, color: c.text))),
                      Text('$nights $nightWord', style: PgText.inter(12.5, FontWeight.w600, color: c.muted)),
                    ]),
                  ),
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
                    for (final p in pets)
                      GestureDetector(
                        onTap: () => setState(() => _petId = p.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: c.surface,
                            border: Border.all(color: _petId == p.id ? c.brand : c.border,
                              width: _petId == p.id ? 2 : 1),
                            borderRadius: BorderRadius.circular(15)),
                          child: Row(children: [
                            const PgImageSlot(size: 44, circle: true),
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
                  ]),
                const SizedBox(height: 8),
                Text('Note to host (optional)', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                PgTextField(label: '', controller: _note, hint: 'Anything the host should know?'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    _priceRow('₹${h.ratePerNight} × $nights $nightWord', '₹$subtotal', c),
                    const SizedBox(height: 9),
                    _priceRow('Service fee', '₹$fee', c),
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
                    label: _saving ? 'Sending…' : 'Send request to $hostFirst',
                    onPressed: _saving ? () {} : () => _send(h, pets)),
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
