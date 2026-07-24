import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

/// Two gates before an irreversible action: an explicit summary of what goes and
/// what stays, then the account password. Firebase requires a recent sign-in to
/// delete anyway, so the password step is both a security check and a pause.
Future<void> showDeleteAccountFlow(BuildContext context, WidgetRef ref) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dCtx) {
      final c = dCtx.pg;
      return AlertDialog(
        backgroundColor: c.surface,
        title: Text('Delete your account?',
            style: PgText.poppins(17, FontWeight.w800, color: c.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This cannot be undone.',
              style: PgText.inter(13.5, FontWeight.w700, color: c.text)),
          const SizedBox(height: 10),
          Text('Deleted: your profile, pets, photos, any pro or homestay listing, '
              'and your Woofs.',
              style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
          const SizedBox(height: 8),
          Text('Kept without your name: reviews, posts and replies you wrote, so '
              'conversations others are reading stay intact.',
              style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
          const SizedBox(height: 8),
          Text('Kept: past bookings, which are payment records shared with the '
              'pro or host involved.',
              style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: Text('Continue', style: PgText.inter(14, FontWeight.w700, color: c.heart))),
        ],
      );
    },
  );
  if (proceed != true || !context.mounted) return;

  final password = await showDialog<String>(
    context: context,
    builder: (dCtx) => const _PasswordPrompt(),
  );
  if (password == null || password.isEmpty || !context.mounted) return;

  // Blocking modal — deletion touches ten collections and must not be
  // interrupted by a stray tap.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final auth = ref.read(authRepositoryProvider);
  try {
    await auth.reauthenticate(password);
    await auth.deleteAccount();
    // Signing out inside deleteAccount flips authStateChanges, and the router
    // redirect takes it from here — no manual navigation needed.
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  } on AuthFailure catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showPgSnack(context, e.message);
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showPgSnack(context, "Couldn't delete your account. Please try again.");
    }
  }
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt();
  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text('Confirm your password',
          style: PgText.poppins(17, FontWeight.w800, color: c.text)),
      content: PgTextField(
        label: '',
        controller: _controller,
        hint: 'Password',
        obscure: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text('Delete account',
                style: PgText.inter(14, FontWeight.w700, color: c.heart))),
      ],
    );
  }
}
