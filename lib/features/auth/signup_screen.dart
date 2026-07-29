import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_choice_card.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/role.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Role _role = Role.petParent;
  bool _loading = false;
  String? _error;

  static const _subtitles = {
    Role.petParent: 'Discover, book, board & chat',
    Role.servicePro: 'Offer walks, grooming & sitting',
    Role.homestayHost: 'Board pets & earn (needs verification)',
  };
  static const _emojis = {
    Role.petParent: '🐾', Role.servicePro: '🎒', Role.homestayHost: '🏡',
  };

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final auth = ref.read(authRepositoryProvider);
      final user = await auth.signUp(email: _email.text.trim(), password: _password.text);
      await ref.read(userRepositoryProvider).createUser(UserProfile(
            uid: user.uid, name: _name.text.trim(), email: _email.text.trim(),
            area: '', role: _role));
      // The account exists but is inert until the emailed link is clicked.
      await auth.sendVerificationEmail();
      if (mounted) context.go(Routes.verifyEmail);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // A funnel step reached only via go(), never pushed — upTo forces Welcome
    // regardless of whatever else happens to be on the stack.
    return PgBackScope(
      upTo: Routes.welcome,
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Column(children: [
            Builder(builder: (ctx) =>
              PgAppBar(title: 'Create account', onBack: () => PgBackScope.pop(ctx))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
                children: [
                  Text('Just a few details to get you and your pet started.',
                      style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                  const SizedBox(height: 13),
                  PgTextField(label: 'Full name', controller: _name, hint: 'Radhika Nair'),
                  const SizedBox(height: 13),
                  PgTextField(label: 'Email', controller: _email,
                      keyboardType: TextInputType.emailAddress, hint: 'you@example.com'),
                  const SizedBox(height: 13),
                  PgTextField(label: 'Password', controller: _password, obscure: true,
                      hint: 'At least 6 characters'),
                  const SizedBox(height: 16),
                  Text("I'M JOINING AS", style: PgText.inter(12.5, FontWeight.w700, color: c.muted)),
                  const SizedBox(height: 10),
                  for (final r in Role.values) ...[
                    PgChoiceCard(
                      emoji: _emojis[r]!, title: r.label, subtitle: _subtitles[r]!,
                      selected: _role == r, onTap: () => setState(() => _role = r)),
                    const SizedBox(height: 10),
                  ],
                  if (_error != null)
                    Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart)),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: PgPrimaryButton(
                label: _loading ? 'Creating…' : 'Continue',
                onPressed: _loading ? () {} : _submit),
            ),
          ]),
        ),
      ),
    );
  }
}
