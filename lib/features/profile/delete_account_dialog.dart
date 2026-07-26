import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';

/// Deleting an account: one dialog, not two.
///
/// This was a full-screen wall of prose followed by a second password dialog.
/// The consequences still have to be stated — Play requires the user to know
/// what deletion actually does — but three paragraphs in a modal is not how
/// anyone reads them, so it is now three short lines and the password lives in
/// the same dialog rather than behind another tap.
Future<void> showDeleteAccountFlow(BuildContext context, WidgetRef ref) =>
    showDialog<void>(context: context, builder: (_) => const _DeleteAccountDialog());

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();
  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    try {
      // Re-auth first: Firebase requires a recent sign-in to delete, and it
      // stops a borrowed unlocked phone from wiping an account.
      await auth.reauthenticate(_password.text);
      await auth.deleteAccount();
      // deleteAccount signs out, which flips authStateChanges and lets the
      // router redirect — no manual navigation needed beyond closing this.
      if (mounted) Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't delete your account. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return AlertDialog(
      backgroundColor: c.surface,
      // Tighter than the Material default, which leaves a lot of dead space
      // around a dialog this short.
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      title: Text('Delete your account?',
          style: PgText.poppins(17, FontWeight.w800, color: c.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This cannot be undone.',
              style: PgText.inter(13.5, FontWeight.w700, color: c.heart)),
          const SizedBox(height: 10),
          _line(c, 'Deleted', 'profile, pets, photos, listings'),
          _line(c, 'Kept, anonymised', 'your reviews, posts and replies'),
          _line(c, 'Kept', 'past bookings — they are payment records'),
          const SizedBox(height: 14),
          PgTextField(
            label: '',
            controller: _password,
            hint: 'Confirm your password',
            obscure: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: PgText.inter(12.5, FontWeight.w600, color: c.heart)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel', style: PgText.inter(14, FontWeight.w600, color: c.muted))),
        TextButton(
            onPressed: _busy ? null : _delete,
            child: Text(_busy ? 'Deleting…' : 'Delete',
                style: PgText.inter(14, FontWeight.w700, color: c.heart))),
      ],
    );
  }

  /// One consequence per line: a bold label and what it covers. Short enough to
  /// actually be read, which the previous paragraphs were not.
  Widget _line(PgColors c, String label, String detail) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ',
              style: PgText.inter(12.5, FontWeight.w700, color: c.text)),
          TextSpan(text: detail,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
      );
}
