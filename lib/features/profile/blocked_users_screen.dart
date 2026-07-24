import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final blockedAsync = ref.watch(blockedUidsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        PgAppBar(title: 'Blocked users', onBack: () => context.pop()),
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
                    for (final uid in blocked)
                      _BlockedRow(uid: uid),
                  ],
                ),
        )),
      ])),
    );
  }
}

class _BlockedRow extends ConsumerWidget {
  final String uid;
  const _BlockedRow({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    // The blocked user's profile doc is still readable, so we can show a name
    // rather than a raw uid. Falls back gracefully if they deleted their account.
    final name = ref.watch(userByIdProvider(uid)).value?.name ?? 'Pawgo user';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(child: Text(name, style: PgText.inter(14, FontWeight.w600, color: c.text))),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final myUid = ref.read(authRepositoryProvider).currentUser?.uid;
            if (myUid == null) return;
            try {
              await ref.read(blockRepositoryProvider).unblock(myUid, uid);
              if (context.mounted) showPgSnack(context, 'Unblocked $name.');
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
