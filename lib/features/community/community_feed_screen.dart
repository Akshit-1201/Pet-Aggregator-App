import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart';
import '../../data/repositories/providers.dart';

class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});
  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  PostCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final postsAsync = ref.watch(postsProvider);

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              decoration: BoxDecoration(color: c.peach,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Community', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
                const SizedBox(height: 3),
                Text('Mumbai pet parents', style: PgText.inter(12.5, FontWeight.w500, color: c.text)),
              ]),
            ),
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
                children: [
                  _catChip('All', _filter == null, () => setState(() => _filter = null), c),
                  for (final cat in PostCategory.values) ...[
                    const SizedBox(width: 9),
                    _catChip('${cat.emoji} ${cat.label}', _filter == cat,
                      () => setState(() => _filter = _filter == cat ? null : cat), c),
                  ],
                ],
              ),
            ),
            Expanded(
              child: postsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load posts.',
                  style: PgText.inter(13.5, FontWeight.w500, color: c.muted))),
                data: (posts) {
                  final list = _filter == null ? posts : posts.where((p) => p.category == _filter).toList();
                  if (list.isEmpty) {
                    return Center(child: Text('No posts yet — start the conversation.',
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
                    children: [
                      for (final p in list) ...[_PostCard(post: p), const SizedBox(height: 12)],
                    ],
                  );
                },
              ),
            ),
          ]),
          Positioned(
            right: 22, bottom: 22,
            child: GestureDetector(
              onTap: () => context.push(Routes.newPost),
              child: Container(
                width: 58, height: 58, alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(19), boxShadow: c.shadow),
                child: const Icon(Icons.add, color: Colors.white, size: 30)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _catChip(String label, bool active, VoidCallback onTap, PgColors c) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.blue : c.surface,
            border: active ? null : Border.all(color: c.border),
            borderRadius: BorderRadius.circular(20)),
          child: Text(label,
            style: PgText.inter(12.5, active ? FontWeight.w700 : FontWeight.w600,
              color: active ? Colors.white : c.text)),
        ),
      );
}

class _PostCard extends StatelessWidget {
  final Post post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final cat = post.category;
    return GestureDetector(
      onTap: () => context.push(Routes.thread, extra: post),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
              child: Text(cat.label, style: PgText.inter(11, FontWeight.w700, color: cat.color))),
            const SizedBox(width: 8),
            Text(Post.timeAgo(post.createdAt), style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
          ]),
          const SizedBox(height: 9),
          Text(post.title, style: PgText.poppins(15, FontWeight.w600, color: c.text)),
          const SizedBox(height: 11),
          Row(children: [
            Text(post.authorName, style: PgText.inter(12, FontWeight.w400, color: c.muted)),
            const SizedBox(width: 14),
            Text('💬 ${post.replyCount}', style: PgText.inter(12, FontWeight.w600, color: c.muted)),
          ]),
        ]),
      ),
    );
  }
}
