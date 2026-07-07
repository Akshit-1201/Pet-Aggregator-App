import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_choice_card.dart';
import '../../core/widgets/pg_field.dart';
import '../../data/models/role.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  Role _role = Role.petParent;

  static const _subtitles = {
    Role.petParent: 'Discover, book, board & chat',
    Role.servicePro: 'Offer walks, grooming & sitting',
    Role.homestayHost: 'Board pets & earn (needs verification)',
  };
  static const _emojis = {
    Role.petParent: '🐾', Role.servicePro: '🎒', Role.homestayHost: '🏡',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Create account', onBack: () => context.go(Routes.welcome)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Text('Just a few details to get you and your pet started.',
                    style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                const SizedBox(height: 13),
                const PgField(label: 'Full name', value: 'Radhika Nair'),
                const SizedBox(height: 13),
                const PgField(label: 'Mobile number', value: '+91 98200 41122'),
                const SizedBox(height: 13),
                const PgField(label: 'Password', value: '', obscure: true),
                const SizedBox(height: 16),
                Text("I'M JOINING AS", style: PgText.inter(12.5, FontWeight.w700, color: c.muted)),
                const SizedBox(height: 10),
                for (final r in Role.values) ...[
                  PgChoiceCard(
                    emoji: _emojis[r]!, title: r.label, subtitle: _subtitles[r]!,
                    selected: _role == r, onTap: () => setState(() => _role = r)),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(label: 'Continue', onPressed: () => context.go(Routes.location)),
          ),
        ]),
      ),
    );
  }
}
