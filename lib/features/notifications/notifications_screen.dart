import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';
import 'notification_item.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final items = ref.watch(notificationsProvider);
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
                  onTap: () => ref.read(userRepositoryProvider).markNotificationsSeen(myUid),
                  child: Text('Mark all read', style: PgText.inter(12.5, FontWeight.w600, color: c.brand))),
            ]),
          ),
          Expanded(child: items.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text("You're all caught up — no notifications yet.",
                  textAlign: TextAlign.center, style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                itemCount: items.length,
                itemBuilder: (_, i) => _NotifRow(item: items[i]),
              )),
        ]),
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final NotificationItem item;
  const _NotifRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.route == null ? null : () => context.push(item.route!, extra: item.extra),
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
            child: Text(item.icon, style: const TextStyle(fontSize: 19))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: PgText.poppins(14, FontWeight.w700, color: c.text)),
            const SizedBox(height: 3),
            Text(item.body, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Post.timeAgo(item.timestamp), style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            if (!item.read) ...[
              const SizedBox(height: 6),
              Container(width: 8, height: 8,
                decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle)),
            ],
          ]),
        ]),
      ),
    );
  }
}
