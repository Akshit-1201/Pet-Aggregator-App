import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/repositories/providers.dart';

/// Blocking has to be reversible somewhere the user can find, or "block" becomes
/// a trap — Play expects an unblock path too.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final blockedAsync = ref.watch(blockedListProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        PgAppBar(title: 'Blocked users', onBack: () => PgBackScope.pop(context)),
        Expanded(child: blockedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load your blocked list.',
              style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
          data: (blocked) => blocked.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text("You haven't blocked anyone.",
                      textAlign: TextAlign.center,
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                  children: [
                    for (final entry in blocked)
                      _BlockedRow(uid: entry.uid, name: entry.name),
                  ],
                ),
        )),
      ])),
    );
  }
}

class _BlockedRow extends ConsumerWidget {
  final String uid;
  final String name;
  const _BlockedRow({required this.uid, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    // Name comes from the block record itself. Looking it up in users/{uid}
    // could never work — that doc is readable only by its owner — so this list
    // used to show "Pawgo user" for everybody.
    final display = name.trim().isEmpty ? 'Pawgo user' : name;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(child: Text(display, style: PgText.inter(14, FontWeight.w600, color: c.text))),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final myUid = ref.read(authRepositoryProvider).currentUser?.uid;
            if (myUid == null) return;
            try {
              await ref.read(blockRepositoryProvider).unblock(myUid, uid);
              if (context.mounted) showPgSnack(context, 'Unblocked $display.');
            } catch (_) {
              if (context.mounted) showPgSnack(context, "Couldn't unblock. Please try again.");
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text('Unblock', style: PgText.inter(13.5, FontWeight.w700, color: c.brand))),
        ),
      ]),
    );
  }
}
