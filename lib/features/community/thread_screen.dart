import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/post.dart';
import '../../data/repositories/providers.dart';

class ThreadScreen extends ConsumerStatefulWidget {
  final Post? post;
  const ThreadScreen({super.key, this.post});
  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(Post post) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    setState(() => _sending = true);
    final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;
    await ref.read(postRepositoryProvider).addComment(post.id, Comment(
        authorId: me.uid, authorName: profile?.name ?? 'Someone', body: text,
        createdAt: DateTime.now().millisecondsSinceEpoch));
    if (!mounted) return;
    _reply.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final post = widget.post;
    if (post == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No post')));
    }
    final commentsAsync = ref.watch(commentsProvider(post.id));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: post.category.label,
              onBack: () => context.canPop() ? context.pop() : context.go(Routes.community)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              children: [
                Text(post.title, style: PgText.poppins(19, FontWeight.w700, color: c.text)),
                const SizedBox(height: 11),
                Row(children: [
                  const PgImageSlot(size: 34, circle: true, emoji: '🙂'),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(post.authorName, style: PgText.inter(12.5, FontWeight.w700, color: c.text)),
                    Text(Post.timeAgo(post.createdAt), style: PgText.inter(11, FontWeight.w400, color: c.faint)),
                  ])),
                ]),
                const SizedBox(height: 12),
                Text(post.body, style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.6)),
                const SizedBox(height: 14),
                Divider(color: c.border),
                const SizedBox(height: 6),
                commentsAsync.when(
                  loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Could not load replies.',
                    style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
                  data: (comments) => comments.isEmpty
                      ? Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No replies yet — be the first.',
                            style: PgText.inter(13.5, FontWeight.w400, color: c.muted)))
                      : Column(children: [
                          for (final cm in comments) ...[_CommentRow(comment: cm), const SizedBox(height: 12)],
                        ]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: EdgeInsets.fromLTRB(16, 11, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  controller: _reply,
                  style: PgText.inter(13.5, FontWeight.w500, color: c.text),
                  cursorColor: c.brand,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: InputBorder.none,
                    hintText: 'Add a reply…',
                    hintStyle: PgText.inter(13.5, FontWeight.w400, color: c.faint)),
                ))),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : () => _send(post),
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

class _CommentRow extends StatelessWidget {
  final Comment comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PgImageSlot(size: 34, circle: true, emoji: '🙂'),
      const SizedBox(width: 11),
      Expanded(child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(15)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(comment.authorName, style: PgText.inter(12.5, FontWeight.w700, color: c.text)),
            const SizedBox(width: 7),
            Text(Post.timeAgo(comment.createdAt), style: PgText.inter(11, FontWeight.w400, color: c.faint)),
          ]),
          const SizedBox(height: 5),
          Text(comment.body, style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.5)),
        ]),
      )),
    ]);
  }
}
