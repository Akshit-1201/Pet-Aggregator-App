import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Confirms [title]/[message], then runs [action]. On failure shows a SnackBar
/// (the booking streams re-emit the true state either way).
Future<void> confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function() action,
}) async {
  final c = context.pg;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(title, style: PgText.poppins(16, FontWeight.w700, color: c.text)),
      content: Text(message, style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Keep', style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(confirmLabel, style: PgText.inter(13.5, FontWeight.w700, color: c.brand))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await action();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update the booking — try again.")));
  }
}
