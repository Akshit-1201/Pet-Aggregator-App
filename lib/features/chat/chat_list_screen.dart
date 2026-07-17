import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/chat.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/repositories/providers.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final chatsAsync = ref.watch(myChatsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PgAppBar(title: 'Messages', onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.search, size: 17, color: c.faint),
                const SizedBox(width: 10),
                Text('Search conversations', style: PgText.inter(13.5, FontWeight.w400, color: c.faint)),
              ]),
            ),
          ),
          Expanded(child: chatsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load messages.',
              style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
            data: (chats) => chats.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Text('No conversations yet — say hi from a match, booking, or host.',
                      textAlign: TextAlign.center, style: PgText.inter(13.5, FontWeight.w400, color: c.muted))))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    children: [for (final chat in chats) _ChatRow(chat: chat, myUid: myUid)],
                  ),
          )),
        ]),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final Chat chat;
  final String myUid;
  const _ChatRow({required this.chat, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final unread = chat.hasUnread(myUid);
    return GestureDetector(
      onTap: () => context.push(Routes.chat, extra: chat),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(children: [
          const PgImageSlot(size: 54, circle: true, emoji: '🙂'),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(chat.otherName(myUid), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
              if (chat.lastMessageAt > 0)
                Text(Post.timeAgo(chat.lastMessageAt), style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(child: Text(chat.lastMessage.isEmpty ? 'Say hi 👋' : chat.lastMessage,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.inter(13, FontWeight.w400, color: unread ? c.text : c.muted))),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(key: const ValueKey('unread-dot'), width: 9, height: 9,
                  decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}
