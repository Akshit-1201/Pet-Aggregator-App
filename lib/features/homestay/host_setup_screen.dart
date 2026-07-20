import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/homestay.dart';
import '../../data/repositories/providers.dart';

class HostSetupScreen extends ConsumerStatefulWidget {
  final bool fromOnboarding;
  const HostSetupScreen({super.key, this.fromOnboarding = false});
  @override
  ConsumerState<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends ConsumerState<HostSetupScreen> {
  final _homeName = TextEditingController();
  final _rate = TextEditingController();
  final _about = TextEditingController();
  HomeType _homeType = HomeType.apartment;
  final Set<Amenity> _amenities = {};
  bool _verified = false;
  double _rating = 0;
  int _reviewCount = 0;
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _homeName.dispose();
    _rate.dispose();
    _about.dispose();
    super.dispose();
  }

  void _seed(Homestay h) {
    _homeName.text = h.homeName;
    _homeType = h.homeType;
    _rate.text = h.ratePerNight.toString();
    _about.text = h.about;
    _amenities
      ..clear()
      ..addAll(h.amenities);
    _verified = h.verified;
    _rating = h.rating;
    _reviewCount = h.reviewCount;
  }

  Future<void> _save() async {
    final name = _homeName.text.trim();
    final rate = int.tryParse(_rate.text.trim()) ?? 0;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a home name.');
      return;
    }
    if (rate <= 0) {
      setState(() => _error = 'Enter a rate greater than 0.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() { _saving = true; _error = null; });
    final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
    await ref.read(homestayRepositoryProvider).upsertHomestay(Homestay(
          uid: uid, homeName: name, hostName: profile?.name ?? '',
          area: profile?.area ?? '', about: _about.text.trim(), homeType: _homeType,
          ratePerNight: rate, amenities: _amenities.toList(),
          verified: _verified, rating: _rating, reviewCount: _reviewCount));
    if (mounted) context.go(Routes.homestay);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    ref.listen(currentHomestayProvider, (prev, next) {
      if (!_seeded && next.hasValue && next.value != null) {
        setState(() => _seed(next.value!));
        _seeded = true;
      }
    });

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(
            title: 'List your home',
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.homestay),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Text('Set up your home so pet parents can book boarding.',
                    style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                const SizedBox(height: 16),
                PgTextField(label: 'Home name', controller: _homeName, hint: "Meera's Home"),
                const SizedBox(height: 16),
                Text('Home type', style: PgText.label(context)),
                const SizedBox(height: 8),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final t in HomeType.values)
                    _SelectChip(
                      label: '${t.emoji} ${t.label}',
                      selected: _homeType == t,
                      onTap: () => setState(() => _homeType = t),
                    ),
                ]),
                const SizedBox(height: 16),
                PgTextField(label: 'Rate (₹ per night)', controller: _rate,
                    keyboardType: TextInputType.number, hint: '900'),
                const SizedBox(height: 16),
                PgTextField(label: 'About this home', controller: _about,
                    hint: 'Tell parents about your home'),
                const SizedBox(height: 16),
                Text('Amenities', style: PgText.label(context)),
                const SizedBox(height: 8),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final a in Amenity.values)
                    _SelectChip(
                      label: '${a.emoji} ${a.label}',
                      selected: _amenities.contains(a),
                      onTap: () => setState(() =>
                          _amenities.contains(a) ? _amenities.remove(a) : _amenities.add(a)),
                    ),
                ]),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(label: _saving ? 'Saving…' : 'List my home',
              onPressed: _saving ? () {} : _save),
          ),
        ]),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          border: Border.all(color: selected ? c.brand : c.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(13)),
        child: Text(label,
          style: PgText.inter(13, FontWeight.w600, color: selected ? c.brand : c.text)),
      ),
    );
  }
}
