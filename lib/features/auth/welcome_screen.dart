import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final auth = ref.read(authRepositoryProvider);
      final user = await auth.signIn(email: _email.text.trim(), password: _password.text);
      // Accounts created before verification existed, or abandoned mid-signup,
      // land here — send a fresh link rather than a dead end.
      if (!user.emailVerified) {
        await auth.sendVerificationEmail();
        if (mounted) context.go(Routes.verifyEmail);
        return;
      }
      if (mounted) context.go(Routes.home);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // The bottom of the auth funnel — no stack, no forced destination.
    // confirmExit matches onboarding page 1, Location and Home, which all
    // guard the same "nowhere up" situation with a second press before
    // exiting, rather than letting a stray press on the login screen kill
    // the app outright.
    return PgBackScope(
      confirmExit: true,
      child: Scaffold(
        body: Stack(children: [
          Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
          ),
          child: Column(children: [
            Expanded(child: Center(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 84, height: 84, alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                  borderRadius: BorderRadius.circular(26)),
                child: const Icon(Icons.pets, size: 46, color: Colors.white)),
              const SizedBox(height: 18),
              Text('Welcome back 👋', style: PgText.poppins(30, FontWeight.w800, color: Colors.white, ls: -0.5)),
              const SizedBox(height: 5),
              Text('Log in to your Pawgo account',
                style: PgText.inter(14, FontWeight.w500, color: const Color(0xFFFFF5E8))),
            ])))),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: c.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                PgTextField(label: 'Email', controller: _email, icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress, hint: 'you@example.com'),
                const SizedBox(height: 14),
                PgTextField(label: 'Password', controller: _password, icon: Icons.lock_outline, obscure: true),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
                const SizedBox(height: 18),
                PgPrimaryButton(label: _loading ? 'Logging in…' : 'Log in',
                  onPressed: _loading ? () {} : _login),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => context.go(Routes.signup),
                  child: Text.rich(TextSpan(text: 'New to Pawgo? ',
                    style: PgText.inter(13.5, FontWeight.w400, color: c.muted),
                    children: [TextSpan(text: 'Create account',
                      style: PgText.inter(13.5, FontWeight.w700, color: c.brand))]))),
              ]),
            ),
          ]),
        ),
          // This is the auth root — there is nowhere up. Builder gives the
          // chevron a context INSIDE PgBackScope's subtree; the outer
          // `context` above is this widget's own, an ancestor of the
          // PgBackScope this build() returns, so PgBackScope.pop(context)
          // would silently degrade to a plain pop instead of confirmExit.
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
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
            ),
          ),
        ]),
      ),
    );
  }
}
