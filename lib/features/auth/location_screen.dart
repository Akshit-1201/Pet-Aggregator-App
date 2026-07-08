import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../data/repositories/providers.dart';

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  Future<void> _continue(WidgetRef ref, BuildContext context) async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid != null) {
      await ref.read(userRepositoryProvider).updateArea(uid, 'Bandra West');
    }
    if (context.mounted) context.go(Routes.createPet);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
          child: Column(children: [
            const Spacer(),
            Container(width: 220, height: 220, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.location_on, size: 92, color: c.brand)),
            const SizedBox(height: 28),
            Text('Enable location', style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 12),
            Text(
              'Pawgo shows pets, pros and homestays near you. We only ever share your approximate area — never your exact address.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const Spacer(),
            PgPrimaryButton(label: 'Allow while using app', onPressed: () => _continue(ref, context)),
            const SizedBox(height: 6),
            PgGhostButton(label: 'Set location manually', onPressed: () => _continue(ref, context)),
          ]),
        ),
      ),
    );
  }
}
