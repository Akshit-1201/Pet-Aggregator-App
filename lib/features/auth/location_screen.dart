import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/maps/area_geo.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';
import 'onboarding_arg.dart';

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
    if (!mounted) return;
    // Read the role deterministically (await the first snapshot) rather than a
    // synchronous read that races the profile stream — same pattern as the
    // pro/host setup _save methods.
    final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
    if (!mounted) return;
    final role = profile?.role ?? Role.petParent;
    final target = switch (role) {
      Role.petParent => Routes.createPet,
      Role.servicePro => Routes.proSetup,
      Role.homestayHost => Routes.hostSetup,
    };
    context.go(target, extra: const OnboardingArg(fromOnboarding: true));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // Reached only from verify-email, so by now the account exists and is
    // verified. Popping to signup would be a dead end and popping to
    // verify-email loops (a verified user is redirected straight off it) —
    // an ordinary confirmed exit is the only sound behaviour here.
    return PgBackScope(
      confirmExit: true,
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Reached only from verify-email with nowhere up (see the
              // PgBackScope note below) — Builder gives the chevron a context
              // INSIDE that scope's subtree, since the outer `context` above
              // is an ancestor of it and would silently degrade to a plain
              // pop instead of running the confirmExit resolver.
              Align(
                alignment: Alignment.centerLeft,
                child: Builder(builder: (ctx) => GestureDetector(
                  onTap: () => PgBackScope.pop(ctx),
                  child: Container(
                    width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(PgRadius.iconBtn)),
                    child: Icon(Icons.chevron_left, color: c.text)),
                )),
              ),
              const SizedBox(height: 10),
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
      ),
    );
  }
}
