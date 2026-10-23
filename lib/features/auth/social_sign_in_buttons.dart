import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';
import 'onboarding_arg.dart';

/// Where a Google, Apple or phone sign-in lands: straight Home for an account
/// that already has a profile, otherwise the short "finish setting up" step.
Future<void> routeAfterSignIn(BuildContext context, WidgetRef ref, SocialSignIn result) async {
  final profile = await ref
      .read(userRepositoryProvider)
      .watchUser(result.user.uid)
      .first
      .timeout(const Duration(seconds: 10), onTimeout: () => null);
  if (!context.mounted) return;
  if (profile != null) {
    context.go(Routes.home);
  } else {
    context.go(Routes.signup, extra: SocialSignupArg(
        name: result.displayName, email: result.user.email ?? '',
        phone: result.user.phoneNumber ?? ''));
  }
}

/// "Continue with Google" (everywhere) and "Sign in with Apple" (iOS), with
/// the "or" divider above the email form.
///
/// One flow for log-in and sign-up alike: the provider either finds an
/// existing Pawgo Pets account or creates one. An account that already has a
/// profile goes straight in; a brand-new one finishes setup on the signup
/// screen with the name prefilled and no password.
class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key});
  @override
  ConsumerState<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  SocialProvider? _busy;

  Future<void> _go(SocialProvider provider) async {
    if (_busy != null) return;
    setState(() => _busy = provider);
    try {
      final result = await ref.read(authRepositoryProvider).signInWithProvider(provider);
      if (result == null || !mounted) return; // cancelled the sheet
      await routeAfterSignIn(context, ref, result);
    } on AuthFailure catch (e) {
      if (mounted) showPgSnack(context, e.message);
    } catch (_) {
      if (mounted) showPgSnack(context, "Couldn't sign you in. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final providers = ref.watch(authRepositoryProvider).availableProviders;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (providers.contains(SocialProvider.apple)) ...[
        // Apple's own button: App Review checks the styling (HIG).
        SizedBox(
          height: 52,
          width: double.infinity,
          child: SignInWithAppleButton(
            key: const Key('social-apple'),
            onPressed: () => _go(SocialProvider.apple),
            text: _busy == SocialProvider.apple ? 'Signing in…' : 'Continue with Apple',
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
        ),
        const SizedBox(height: 10),
      ],
      GestureDetector(
        key: const Key('social-phone'),
        onTap: _busy != null ? null : () => context.push(Routes.phoneSignIn),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border, width: 1.5),
            borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.phone_iphone_rounded, size: 20, color: c.text),
            const SizedBox(width: 10),
            Flexible(child: Text('Continue with phone', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.inter(15, FontWeight.w600, color: c.text))),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      if (providers.contains(SocialProvider.google))
        GestureDetector(
          key: const Key('social-google'),
          onTap: () => _go(SocialProvider.google),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border, width: 1.5),
              borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _GoogleG(),
              const SizedBox(width: 10),
              Flexible(child: Text(_busy == SocialProvider.google ? 'Signing in…' : 'Continue with Google',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: PgText.inter(15, FontWeight.w600, color: c.text))),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Container(height: 1, color: c.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or use email', style: PgText.inter(12.5, FontWeight.w500, color: c.faint))),
        Expanded(child: Container(height: 1, color: c.border)),
      ]),
      const SizedBox(height: 14),
    ]);
  }
}

/// The multicolour "G", drawn as text so it needs no image asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const SweepGradient(colors: [
          Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4),
        ]).createShader(r),
        child: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
      );
}
