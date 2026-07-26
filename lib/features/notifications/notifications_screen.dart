import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/notification_record.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final items = ref.watch(notificationsProvider).value ?? const <NotificationRecord>[];
    final hasUnread = ref.watch(hasUnreadNotificationsProvider);
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.chevron_left, color: c.text))),
              const SizedBox(width: 14),
              Expanded(child: Text('Notifications',
                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
              if (hasUnread)
                GestureDetector(
                  onTap: () =>
                      ref.read(notificationRepositoryProvider).markAllRead(myUid),
                  child: Text('Mark all read',
                    style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
            ]),
          ),
          Expanded(child: items.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text("You're all caught up — no notifications yet.",
                  textAlign: TextAlign.center,
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                itemCount: items.length,
                itemBuilder: (_, i) => _NotifRow(item: items[i], myUid: myUid),
              )),
        ]),
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
          await ref.read(notificationRepositoryProvider).markRead(myUid, item.id);
        }
        if (!context.mounted || item.route.isEmpty) return;
        context.go(item.route);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: item.read ? c.surface : c.brandSoft,
          border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13)),
            child: Text(item.emoji, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: PgText.inter(13.5, FontWeight.w700, color: c.text)),
            const SizedBox(height: 2),
            Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 4),
            Text(Post.timeAgo(item.createdAt),
              style: PgText.inter(11, FontWeight.w400, color: c.muted)),
          ])),
        ]),
      ),
    );
  }
}
