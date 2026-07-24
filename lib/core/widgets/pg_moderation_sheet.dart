import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/report.dart';
import '../../data/repositories/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'pg_snackbar.dart';

/// One entry point for "report this" / "block them", used by every surface that
/// shows another person's content, so the flow reads the same everywhere.
///
/// Google Play's UGC policy requires both an in-app report path and an in-app
/// block path; keeping them in a single sheet means adding a new surface is one
/// call rather than a re-implementation.
Future<void> showModerationSheet(
  BuildContext context,
  WidgetRef ref, {
  required ReportTargetType targetType,
  required String targetId,
  String targetOwnerId = '',
  String targetOwnerName = '',
  String contextId = '',
}) async {
  final c = context.pg;
  final myUid = ref.read(authRepositoryProvider).currentUser?.uid;
  // Blocking is only offered when we know who authored the thing, and never
  // against yourself.
  final canBlock = targetOwnerId.isNotEmpty && targetOwnerId != myUid;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Report or block', style: PgText.poppins(18, FontWeight.w800, color: c.text)),
          const SizedBox(height: 4),
          Text('Reports go to the Pawgo team. Blocking is instant and only affects you.',
              style: PgText.inter(13, FontWeight.w400, color: c.muted)),
          const SizedBox(height: 16),
          _sheetRow(sheetCtx, c, '🚩', 'Report this ${targetType.noun}',
              'Tell us what is wrong with it', () {
            Navigator.of(sheetCtx).pop();
            _showReasonPicker(context, ref,
                targetType: targetType, targetId: targetId,
                targetOwnerId: targetOwnerId, contextId: contextId);
          }),
          if (canBlock) ...[
            const SizedBox(height: 10),
            _sheetRow(sheetCtx, c, '🚫',
                targetOwnerName.isEmpty ? 'Block this person' : 'Block $targetOwnerName',
                'Hide them across Pawgo and stop their messages', () {
              Navigator.of(sheetCtx).pop();
              _confirmBlock(context, ref, targetOwnerId, targetOwnerName);
            }),
          ],
        ]),
      ),
    ),
  );
}

Future<void> _showReasonPicker(
  BuildContext context,
  WidgetRef ref, {
  required ReportTargetType targetType,
  required String targetId,
  required String targetOwnerId,
  required String contextId,
}) async {
  final c = context.pg;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("What's wrong?", style: PgText.poppins(18, FontWeight.w800, color: c.text)),
          const SizedBox(height: 14),
          for (final reason in ReportReason.values) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                final myUid = ref.read(authRepositoryProvider).currentUser?.uid;
                if (myUid == null) return;
                try {
                  await ref.read(reportRepositoryProvider).submitReport(Report(
                        reporterId: myUid,
                        targetType: targetType,
                        targetId: targetId,
                        targetOwnerId: targetOwnerId,
                        contextId: contextId,
                        reason: reason,
                        createdAt: DateTime.now().millisecondsSinceEpoch,
                      ));
                  if (context.mounted) {
                    showPgSnack(context, 'Thanks — the Pawgo team will take a look.');
                  }
                } catch (_) {
                  if (context.mounted) {
                    showPgSnack(context, "Couldn't send that report. Please try again.");
                  }
                }
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                decoration: BoxDecoration(
                    color: c.surface2, borderRadius: BorderRadius.circular(14)),
                child: Text(reason.label,
                    style: PgText.inter(14, FontWeight.w600, color: c.text)),
              ),
            ),
          ],
        ]),
      ),
    ),
  );
}

Future<void> _confirmBlock(
    BuildContext context, WidgetRef ref, String blockedUid, String name) async {
  final c = context.pg;
  final who = name.isEmpty ? 'this person' : name;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('Block $who?', style: PgText.poppins(17, FontWeight.w800, color: c.text)),
      content: Text(
          "You won't see their posts, listings or pets, and they won't be able to message you. "
          'You can undo this in Settings.',
          style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text('Block', style: PgText.inter(14, FontWeight.w700, color: c.heart))),
      ],
    ),
  );
  if (ok != true) return;
  final myUid = ref.read(authRepositoryProvider).currentUser?.uid;
  if (myUid == null) return;
  try {
    await ref.read(blockRepositoryProvider).block(myUid, blockedUid);
    if (context.mounted) showPgSnack(context, 'Blocked. You can undo this in Settings.');
  } catch (_) {
    if (context.mounted) showPgSnack(context, "Couldn't block them. Please try again.");
  }
}

Widget _sheetRow(BuildContext context, PgColors c, String emoji, String title,
        String subtitle, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: c.brandSoft,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(15, FontWeight.w700, color: c.text)),
            Text(subtitle, style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          Icon(Icons.chevron_right, color: c.faint, size: 20),
        ]),
      ),
    );
