import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/chat.dart';
import '../../data/repositories/providers.dart';

class ChatConversationScreen extends ConsumerStatefulWidget {
  final Chat? chat;
  const ChatConversationScreen({super.key, this.chat});
  @override
  ConsumerState<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends ConsumerState<ChatConversationScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final chat = widget.chat;
    final me = ref.read(authRepositoryProvider).currentUser;
    if (chat != null && me != null) {
      ref.read(chatRepositoryProvider).markRead(chatId: chat.id, uid: me.uid);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(Chat chat, String myUid) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await ref.read(chatRepositoryProvider).sendMessage(chatId: chat.id, senderId: myUid, text: text);
    if (!mounted) return;
    _input.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final chat = widget.chat;
    if (chat == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No conversation')));
    }
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final otherName = chat.otherName(myUid);
    final messagesAsync = ref.watch(chatMessagesProvider(chat.id));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          // header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 16, 10),
            decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: SizedBox(width: 40, height: 40,
                  child: Icon(Icons.chevron_left, color: c.text))),
              const PgImageSlot(size: 42, circle: true, emoji: '🙂'),
              const SizedBox(width: 11),
              Expanded(child: Text(otherName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(15, FontWeight.w700, color: c.text))),
              GestureDetector(
                onTap: () => showComingSoon(context, 'Calls'),
                child: Icon(Icons.call_outlined, color: c.muted, size: 21)),
            ]),
          ),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load messages.',
                style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
              data: (messages) {
                final masked = messages.any((m) => m.text.contains('••••'));
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  children: [
                    for (final m in messages) _Bubble(mine: m.senderId == myUid, text: m.text),
                    if (masked) ...[
                      const SizedBox(height: 8),
                      _SafetyNotice(c: c),
                    ],
                  ],
                );
              },
            ),
          ),
          // composer
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: EdgeInsets.fromLTRB(16, 11, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  controller: _input,
                  style: PgText.inter(13.5, FontWeight.w500, color: c.text),
                  cursorColor: c.brand,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: InputBorder.none,
                    hintText: 'Message…',
                    hintStyle: PgText.inter(13.5, FontWeight.w400, color: c.faint)),
                ))),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : () => _send(chat, myUid),
                child: Container(
                  width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]), shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 19))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool mine;
  final String text;
  const _Bubble({required this.mine, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: mine ? LinearGradient(colors: [c.brand, c.brand2]) : null,
          color: mine ? null : c.surface,
          border: mine ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16))),
        child: Text(text, style: PgText.inter(14, FontWeight.w400, color: mine ? Colors.white : c.text, height: 1.35)),
      ),
    );
  }
}

class _SafetyNotice extends StatelessWidget {
  final PgColors c;
  const _SafetyNotice({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
      child: Text('🛡️ Pawgo hid a phone number to keep your chat safe. Share contact details only after you meet.',
        textAlign: TextAlign.center, style: PgText.inter(12, FontWeight.w500, color: c.brandDeep, height: 1.4)),
    ));
  }
}
