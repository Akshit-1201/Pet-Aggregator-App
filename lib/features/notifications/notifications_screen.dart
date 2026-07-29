import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/notification_record.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final items =
        ref.watch(notificationsProvider).value ?? const <NotificationRecord>[];
    final hasUnread = ref.watch(hasUnreadNotificationsProvider);
    // Same source as notificationsProvider (authStateProvider), not
    // authRepositoryProvider.currentUser — during a sign-in/out transition the
    // two can disagree, and a mismatched uid makes markRead/markAllRead a
    // rules-rejected no-op against the wrong path.
    final myUid = ref.watch(authStateProvider).value?.uid ?? '';

    return PgBackScope(
      // Cold-start deep link and push-notification tap both `go` here with
      // the stack wiped, but it is also legitimately pushed from Home —
      // upToIfEmpty keeps a real pop when a parent exists and only falls
      // back to Home when there is nothing to pop to.
      upToIfEmpty: Routes.home,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (ctx) => PgAppBar(
                        title: 'Notifications',
                        onBack: () => PgBackScope.pop(ctx),
                      ),
                    ),
                  ),
                  if (hasUnread)
                    Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(notificationRepositoryProvider)
                            .markAllRead(myUid),
                        child: Text(
                          'Mark all read',
                          style: PgText.inter(
                            12.5,
                            FontWeight.w600,
                            color: c.brand,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Text(
                            "You're all caught up — no notifications yet.",
                            textAlign: TextAlign.center,
                            style: PgText.inter(
                              13.5,
                              FontWeight.w400,
                              color: c.muted,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                        itemCount: items.length,
                        itemBuilder: (_, i) =>
                            _NotifRow(item: items[i], myUid: myUid),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifRow extends ConsumerWidget {
  final NotificationRecord item;
  final String myUid;
  const _NotifRow({required this.item, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (!item.read) {
          await ref
              .read(notificationRepositoryProvider)
              .markRead(myUid, item.id);
        }
        if (!context.mounted || item.route.isEmpty) return;
        context.go(item.route);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: item.read ? c.surface : c.brandSoft,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(item.emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: PgText.inter(13.5, FontWeight.w700, color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PgText.inter(12.5, FontWeight.w400, color: c.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Post.timeAgo(item.createdAt),
                    style: PgText.inter(11, FontWeight.w400, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
