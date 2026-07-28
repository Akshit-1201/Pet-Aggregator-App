import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
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
import '../payouts/earnings_card.dart';

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

    // Rebuilds this subtree whenever a tracked controller changes, so
    // PopScope's canPop (baked in at build time) reflects the current dirty
    // state — plain text edits otherwise never trigger a rebuild here, since
    // PgTextField has no onChanged wired to setState.
    return ListenableBuilder(
      listenable: Listenable.merge([_rate, _exp, _bio]),
      builder: (context, _) => PgBackScope(
        // Only text fields here — no photos, so a listing's costliest field to
        // retype (the bio) stands in for the "expensive" case.
        confirmWhen: () =>
            _rate.text.trim().isNotEmpty ||
            _exp.text.trim().isNotEmpty ||
            _bio.text.trim().isNotEmpty,
        confirmMessage: "Your service listing isn't saved yet. Leaving now discards it.",
        child: Scaffold(
          backgroundColor: c.surface,
          body: SafeArea(
            child: Column(children: [
              Builder(builder: (ctx) =>
                PgAppBar(title: 'Offer your services', onBack: () => PgBackScope.pop(ctx))),
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
                    const SizedBox(height: 14),
                    const EarningsCard(),
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
        ),
      ),
    );
  }
}
