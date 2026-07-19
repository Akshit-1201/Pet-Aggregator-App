import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/maps/area_geo.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/homestay.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';
import 'nearby_markers.dart';

/// Builds the map view — swapped for a stub in widget tests (GoogleMap is a
/// platform view that cannot render under flutter_test).
typedef MapViewBuilder = Widget Function(CameraPosition initialCamera, Set<Marker> markers);

final mapViewBuilderProvider = Provider<MapViewBuilder>((ref) =>
    (initialCamera, markers) => GoogleMap(
          initialCameraPosition: initialCamera,
          markers: markers,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
        ));

class NearbyMapScreen extends ConsumerStatefulWidget {
  const NearbyMapScreen({super.key});
  @override
  ConsumerState<NearbyMapScreen> createState() => _NearbyMapScreenState();
}

class _NearbyMapScreenState extends ConsumerState<NearbyMapScreen> {
  NearbyLayer _layer = NearbyLayer.pets;
  PetPinFilter _petFilter = PetPinFilter.all;

  static const _chips = <(String, NearbyLayer, PetPinFilter?)>[
    ('All pets', NearbyLayer.pets, PetPinFilter.all),
    ('🐶 Dogs', NearbyLayer.pets, PetPinFilter.dogs),
    ('🐱 Cats', NearbyLayer.pets, PetPinFilter.cats),
    ('✓ Vaccinated', NearbyLayer.pets, PetPinFilter.vaccinated),
    ('🧑 Pros', NearbyLayer.pros, null),
    ('🏡 Homestays', NearbyLayer.homestays, null),
  ];

  void _woof(PetProfile pet) {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.woof));
  }

  bool _chipSelected((String, NearbyLayer, PetPinFilter?) chip) =>
      chip.$2 == _layer && (chip.$3 == null || chip.$3 == _petFilter);

  Widget _chip(PgColors c, (String, NearbyLayer, PetPinFilter?) chip) {
    final sel = _chipSelected(chip);
    return GestureDetector(
      onTap: () => setState(() {
        _layer = chip.$2;
        if (chip.$3 != null) _petFilter = chip.$3!;
      }),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: sel ? c.brand : c.surface,
          border: sel ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20)),
        child: Text(chip.$1,
          style: PgText.inter(12.5, FontWeight.w600, color: sel ? Colors.white : c.text))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final pets = ref.watch(nearbyPetsProvider).value ?? const <PetProfile>[];
    final pros = ref.watch(prosProvider).value ?? const <Pro>[];
    final homestays = ref.watch(homestaysProvider).value ?? const <Homestay>[];
    final myArea = ref.watch(currentUserProfileProvider).value?.area ?? fallbackArea;

    final specs = buildPins(
        layer: _layer, petFilter: _petFilter, pets: pets, pros: pros, homestays: homestays);
    final markers = {
      for (final s in specs)
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(s.hue),
          infoWindow: InfoWindow(
            title: s.title, snippet: s.snippet,
            onTap: () => context.push(s.route, extra: s.extra)),
        ),
    };
    final c0 = centroidFor(myArea);
    final initialCamera = CameraPosition(target: LatLng(c0.lat, c0.lng), zoom: 13.5);
    final mapBuilder = ref.watch(mapViewBuilderProvider);

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: mapBuilder(initialCamera, markers)),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => context.go(Routes.discover),
                  child: Container(
                    width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.chevron_left, color: c.text))),
                const SizedBox(width: 12),
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16), boxShadow: c.shadow),
                  child: Text('🔍  Search pets near you',
                    style: PgText.inter(14, FontWeight.w500, color: c.muted)))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              // A plain scrollable Row rather than ListView.separated: this
              // chip set is small and fixed (6 items), and Row's children —
              // unlike a Sliver-backed ListView's — are never treated as
              // "offstage" once they scroll past the visible viewport, so
              // every chip stays reliably hit-testable (incl. in widget
              // tests, which skip offstage widgets by default).
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < _chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 9),
                    _chip(c, _chips[i]),
                  ],
                ]),
              ),
            ),
            const Spacer(),
            _sheet(c, pets, pros, homestays),
          ]),
        ),
      ]),
    );
  }

  Widget _sheet(PgColors c, List<PetProfile> pets, List<Pro> pros, List<Homestay> homestays) {
    final filteredPets = [
      for (final p in pets)
        if (switch (_petFilter) {
          PetPinFilter.all => true,
          PetPinFilter.dogs => p.species == Species.dog,
          PetPinFilter.cats => p.species == Species.cat,
          PetPinFilter.vaccinated => p.vaccinated,
        }) p,
    ];
    final (String header, int count) = switch (_layer) {
      NearbyLayer.pets => ('pets nearby', filteredPets.length),
      NearbyLayer.pros => ('pros nearby', pros.length),
      NearbyLayer.homestays => ('homestays nearby', homestays.length),
    };

    return Container(
      decoration: BoxDecoration(
        color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 30, offset: Offset(0, -10))]),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$count $header', style: PgText.poppins(16, FontWeight.w700, color: c.text)),
          if (_layer == NearbyLayer.pets)
            GestureDetector(onTap: () => context.go(Routes.discover),
              child: Text('Swipe view →', style: PgText.inter(12.5, FontWeight.w700, color: c.brand))),
        ]),
        const SizedBox(height: 12),
        if (_layer == NearbyLayer.pets)
          for (final p in filteredPets.take(4))
            _row(c, emoji: '🐾', imageUrl: p.photoUrl, title: p.name,
              subtitle: '${p.breed} · ${p.area}',
              onTap: () => context.push(Routes.petProfile, extra: p),
              trailing: GestureDetector(
                onTap: () => _woof(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text('Woof!', style: PgText.poppins(12.5, FontWeight.w700, color: Colors.white))))),
        if (_layer == NearbyLayer.pros)
          for (final p in pros.take(4))
            _row(c, emoji: '🧑', imageUrl: null, title: p.name,
              subtitle: '${p.serviceType.label} · ₹${p.rate}/${p.unit}',
              onTap: () => context.push(Routes.servicePro, extra: p)),
        if (_layer == NearbyLayer.homestays)
          for (final h in homestays.take(4))
            _row(c, emoji: '🏡', imageUrl: null, title: h.homeName,
              subtitle: '${h.hostName} · ₹${h.ratePerNight}/night',
              onTap: () => context.push(Routes.host, extra: h)),
      ]),
    );
  }

  Widget _row(PgColors c, {required String emoji, String? imageUrl, required String title,
      required String subtitle, required VoidCallback onTap, Widget? trailing}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          PgImageSlot(size: 50, circle: true, emoji: emoji, imageUrl: imageUrl),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          ?trailing,
        ]),
      ),
    );
  }
}
