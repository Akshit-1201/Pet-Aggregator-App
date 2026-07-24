import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

/// The gate between signing up and using Pawgo.
///
/// Clicking the verification link happens in a browser, and nothing pushes that
/// back into the app — `authStateChanges()` does not fire for it. So the app has
/// to ask Firebase: this screen polls every few seconds and also offers an
/// explicit button, rather than leaving someone stuck on a screen that looks
/// broken after they have already verified.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _poll;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Most people verify within a few seconds of landing here, so poll rather
    // than make them come back and tap.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 45);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendCooldown--);
      if (_resendCooldown <= 0) t.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final verified = await ref.read(authRepositoryProvider).refreshEmailVerified();
      if (!mounted) return;
      if (verified) {
        _poll?.cancel();
        // Straight into the funnel — the profile doc already exists from signup.
        context.go(Routes.location);
      } else if (!silent) {
        showPgSnack(context, "Not verified yet — check your inbox, and your spam folder.");
      }
    } catch (_) {
      if (mounted && !silent) {
        showPgSnack(context, "Couldn't check just now. Please try again.");
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).sendVerificationEmail();
      if (mounted) {
        showPgSnack(context, 'Verification email sent.');
        _startCooldown();
      }
    } on AuthFailure catch (e) {
      if (mounted) showPgSnack(context, e.message);
    } catch (_) {
      if (mounted) showPgSnack(context, "Couldn't send that email. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final email = ref.watch(authRepositoryProvider).currentUser?.email ?? 'your email';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Column(children: [
            const Spacer(),
            const Text('📬', style: TextStyle(fontSize: 58)),
            const SizedBox(height: 20),
            Text('Confirm your email',
                textAlign: TextAlign.center,
                style: PgText.poppins(23, FontWeight.w800, color: c.text)),
            const SizedBox(height: 10),
            Text('We sent a link to', textAlign: TextAlign.center,
                style: PgText.inter(14, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 3),
            Text(email, textAlign: TextAlign.center,
                style: PgText.inter(14.5, FontWeight.w700, color: c.text)),
            const SizedBox(height: 14),
            Text('Tap it, then come back here. This keeps Pawgo free of fake '
                'accounts so pet parents and pros can trust each other.',
                textAlign: TextAlign.center,
                style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.55)),
            const Spacer(),
            PgPrimaryButton(label: "I've confirmed it", onPressed: _check),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _resendCooldown > 0 ? null : _resend,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    _resendCooldown > 0
                        ? 'Resend email in ${_resendCooldown}s'
                        : 'Resend email',
                    textAlign: TextAlign.center,
                    style: PgText.inter(13.5, FontWeight.w700,
                        color: _resendCooldown > 0 ? c.faint : c.brand)),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(authRepositoryProvider).signOut(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Use a different email',
                    textAlign: TextAlign.center,
                    style: PgText.inter(13, FontWeight.w600, color: c.muted)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
