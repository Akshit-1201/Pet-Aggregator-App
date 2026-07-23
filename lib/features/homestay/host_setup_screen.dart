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
  final List<String> _photos = [];
  bool _verified = false;
  double _rating = 0;
  int _reviewCount = 0;
  bool _seeded = false;
  bool _saving = false;
  bool _uploading = false;
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
    _photos
      ..clear()
      ..addAll(h.photoUrls);
    _verified = h.verified;
    _rating = h.rating;
    _reviewCount = h.reviewCount;
  }

  /// Pick one photo and upload it immediately, so the host sees a real thumbnail
  /// and the saved listing only ever holds URLs that already exist in Storage.
  Future<void> _addPhoto() async {
    if (_uploading || _photos.length >= Homestay.maxPhotos) return;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (!mounted || bytes == null) return;
      setState(() { _uploading = true; _error = null; });
      final url = await ref.read(storageRepositoryProvider).uploadImage(
          path: 'homestays/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: bytes);
      if (!mounted) return;
      setState(() => _photos.add(url));
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't upload that photo. Please try again.");
    } finally {
      if (mounted && _uploading) setState(() => _uploading = false);
    }
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
    if (_photos.length < Homestay.minPhotos) {
      setState(() => _error =
          'Add at least ${Homestay.minPhotos} photos of your home (${_photos.length} so far).');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() { _saving = true; _error = null; });
    final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
    await ref.read(homestayRepositoryProvider).upsertHomestay(Homestay(
          uid: uid, homeName: name, hostName: profile?.name ?? '',
          area: profile?.area ?? '', about: _about.text.trim(), homeType: _homeType,
          ratePerNight: rate, amenities: _amenities.toList(), photoUrls: List.of(_photos),
          verified: _verified, rating: _rating, reviewCount: _reviewCount));
    if (mounted) _exit();
  }

  void _exit() =>
      context.go(widget.fromOnboarding ? Routes.home : Routes.homestay);

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
            onBack: () => widget.fromOnboarding
                ? _exit()
                : (context.canPop() ? context.pop() : context.go(Routes.homestay)),
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
                Row(children: [
                  Expanded(child: Text('Photos of your home', style: PgText.label(context))),
                  Text('${_photos.length}/${Homestay.maxPhotos}',
                      style: PgText.inter(12.5, FontWeight.w600,
                          color: _photos.length < Homestay.minPhotos ? c.heart : c.brand)),
                ]),
                const SizedBox(height: 4),
                Text('Add ${Homestay.minPhotos}–${Homestay.maxPhotos} photos so parents can see the place.',
                    style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                const SizedBox(height: 10),
                _photoStrip(c),
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
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Beside the button, not at the end of the scrolling form — otherwise
              // the reason a save was refused is off-screen when you tap Save.
              if (_error != null) ...[
                Text(_error!, textAlign: TextAlign.center,
                    style: PgText.inter(13, FontWeight.w600, color: c.heart)),
                const SizedBox(height: 10),
              ],
              PgPrimaryButton(label: _saving ? 'Saving…' : 'List my home',
                onPressed: _saving ? () {} : _save),
              if (widget.fromOnboarding) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _saving ? null : () => context.go(Routes.home),
                  child: Text('Set up later',
                    style: PgText.inter(13.5, FontWeight.w600, color: context.pg.muted))),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
  Widget _photoStrip(PgColors c) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < _photos.length; i++)
          Stack(children: [
            SizedBox(width: 92, height: 92,
                child: PgImageSlot(radius: 14, emoji: '🏡', imageUrl: _photos[i])),
            Positioned(
              top: 4, right: 4,
              child: GestureDetector(
                key: Key('remove-photo-$i'),
                onTap: () => setState(() => _photos.removeAt(i)),
                child: Container(
                  width: 24, height: 24, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 15, color: Colors.white)),
              ),
            ),
          ]),
        if (_photos.length < Homestay.maxPhotos)
          GestureDetector(
            key: const Key('add-home-photo'),
            onTap: _uploading ? null : _addPhoto,
            child: Container(
              width: 92, height: 92, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface2, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border)),
              child: _uploading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_a_photo_outlined, color: c.muted, size: 22),
                      const SizedBox(height: 4),
                      Text('Add', style: PgText.inter(12, FontWeight.w600, color: c.muted)),
                    ]),
            ),
          ),
      ]);
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
