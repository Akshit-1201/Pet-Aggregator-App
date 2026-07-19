import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/maps/area_geo.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../data/repositories/providers.dart';

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  String _selected = fallbackArea;
  bool _saving = false;

  Future<void> _continue() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).updateArea(uid, _selected);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text("Couldn't save your area. Please try again."),
            behavior: SnackBarBehavior.floating));
      }
      return;
    }
    if (mounted) context.go(Routes.createPet);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(
              width: 96, height: 96, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.location_on, size: 44, color: c.brand))),
            const SizedBox(height: 18),
            Text('Choose your area', textAlign: TextAlign.center,
              style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 8),
            Text(
              'Pawgo shows pets, pros and homestays near you. We only ever share your approximate area — never your exact address.',
              textAlign: TextAlign.center,
              style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.5)),
            const SizedBox(height: 18),
            Expanded(child: ListView(children: [
              for (final area in areaNames)
                GestureDetector(
                  onTap: () => setState(() => _selected = area),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _selected == area ? c.brandSoft : null,
                      border: Border.all(
                        color: _selected == area ? c.brand : c.border,
                        width: _selected == area ? 2 : 1),
                      borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(child: Text(area,
                        style: PgText.inter(14, FontWeight.w600,
                          color: _selected == area ? c.brand : c.text))),
                      if (_selected == area) Icon(Icons.check_circle, size: 18, color: c.brand),
                    ]),
                  ),
                ),
            ])),
            const SizedBox(height: 12),
            PgPrimaryButton(
              label: _saving ? 'Saving…' : 'Continue',
              onPressed: _saving ? () {} : _continue),
          ]),
        ),
      ),
    );
  }
}
