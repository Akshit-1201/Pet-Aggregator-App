import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_field.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
        ),
        child: Column(children: [
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 84, height: 84, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                    borderRadius: BorderRadius.circular(26)),
                  child: const Icon(Icons.pets, size: 46, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text('Welcome back 👋', style: PgText.poppins(30, FontWeight.w800, color: Colors.white, ls: -0.5)),
                const SizedBox(height: 5),
                Text('Log in to your Pawgo account',
                    style: PgText.inter(14, FontWeight.w500, color: const Color(0xFFFFF5E8))),
              ]),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const PgField(label: '', value: '+91 98200 41122', icon: Icons.phone_outlined),
              const SizedBox(height: 14),
              const PgField(label: '', value: '', icon: Icons.lock_outline, obscure: true),
              const SizedBox(height: 18),
              PgPrimaryButton(label: 'Log in', onPressed: () => context.go(Routes.home)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => context.go(Routes.signup),
                child: Text.rich(TextSpan(
                  text: 'New to Pawgo? ',
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted),
                  children: [TextSpan(text: 'Create account',
                      style: PgText.inter(13.5, FontWeight.w700, color: c.brand))],
                )),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
