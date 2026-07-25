import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/pro.dart';
import '../../data/models/verification_request.dart';
import '../../data/repositories/providers.dart';
import '../verification/verification_card.dart';

class ProSetupScreen extends ConsumerStatefulWidget {
  final bool fromOnboarding;
  const ProSetupScreen({super.key, this.fromOnboarding = false});
  @override
  ConsumerState<ProSetupScreen> createState() => _ProSetupScreenState();
}

class _ProSetupScreenState extends ConsumerState<ProSetupScreen> {
  final _rate = TextEditingController();
  final _exp = TextEditingController();
  final _bio = TextEditingController();
  ServiceType _type = ServiceType.walker;
  double _rating = 0;
  int _reviewCount = 0;
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    _exp.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _seed(Pro p) {
    _type = p.serviceType;
    _rate.text = p.rate.toString();
    _exp.text = p.experienceYears.toString();
    _bio.text = p.bio;
    _rating = p.rating;
    _reviewCount = p.reviewCount;
  }

  Future<void> _save() async {
    final rate = int.tryParse(_rate.text.trim()) ?? 0;
    if (rate <= 0) {
      setState(() => _error = 'Enter a rate greater than 0.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() { _saving = true; _error = null; });
    final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
    await ref.read(proRepositoryProvider).upsertPro(Pro(
          uid: uid, name: profile?.name ?? '', area: profile?.area ?? '',
          bio: _bio.text.trim(), serviceType: _type, rate: rate,
          experienceYears: int.tryParse(_exp.text.trim()) ?? 0,
          rating: _rating, reviewCount: _reviewCount));
    if (mounted) _exit();
  }

  void _exit() =>
      context.go(widget.fromOnboarding ? Routes.home : Routes.services);

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    ref.listen(currentProProvider, (prev, next) {
      if (!_seeded && next.hasValue && next.value != null) {
        setState(() => _seed(next.value!));
        _seeded = true;
      }
    });

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Offer your services', onBack: _exit),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Text('Set up your listing so pet parents can find and book you.',
                    style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                const SizedBox(height: 16),
                Text('Service type', style: PgText.label(context)),
                const SizedBox(height: 8),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final t in ServiceType.values)
                    GestureDetector(
                      onTap: () => setState(() => _type = t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _type == t ? c.brandSoft : c.surface,
                          border: Border.all(color: _type == t ? c.brand : c.border, width: _type == t ? 2 : 1),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text('${t.emoji} ${t.label}',
                          style: PgText.inter(13, FontWeight.w600, color: _type == t ? c.brand : c.text)),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                PgTextField(label: 'Rate (₹ per ${_type.unit})', controller: _rate,
                    keyboardType: TextInputType.number, hint: '250'),
                const SizedBox(height: 14),
                PgTextField(label: 'Experience (years)', controller: _exp,
                    keyboardType: TextInputType.number, hint: '4'),
                const SizedBox(height: 14),
                PgTextField(label: 'About you', controller: _bio, hint: 'Tell parents about yourself'),
                const SizedBox(height: 18),
                // Optional — an unverified pro can still list, they just don't
                // get the badge. Kept below the listing fields so it never
                // blocks someone from going live.
                const VerificationCard(kind: VerificationKind.pro),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PgPrimaryButton(label: _saving ? 'Saving…' : 'Save listing',
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
}
