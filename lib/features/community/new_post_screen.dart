import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/post.dart';
import '../../data/repositories/providers.dart';

class NewPostScreen extends ConsumerStatefulWidget {
  const NewPostScreen({super.key});
  @override
  ConsumerState<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends ConsumerState<NewPostScreen> {
  PostCategory _category = PostCategory.health;
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _posting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Add a title.');
      return;
    }
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    setState(() { _posting = true; _error = null; });
    final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;
    final created = await ref.read(postRepositoryProvider).createPost(Post(
        authorId: me.uid, authorName: profile?.name ?? 'Someone', category: _category,
        title: title, body: _body.text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch));
    if (mounted) context.go(Routes.postLive, extra: created);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'New post', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Text('CATEGORY', style: PgText.inter(12.5, FontWeight.w700, color: c.muted)),
                const SizedBox(height: 9),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final cat in PostCategory.values)
                    GestureDetector(
                      onTap: () => setState(() => _category = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                        decoration: BoxDecoration(
                          color: _category == cat ? c.brand : c.surface,
                          border: _category == cat ? null : Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text('${cat.emoji} ${cat.label}',
                          style: PgText.inter(13, FontWeight.w600,
                            color: _category == cat ? Colors.white : c.text)),
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
                PgTextField(label: 'Title', controller: _title, hint: 'Ask the community…'),
                const SizedBox(height: 16),
                PgTextField(label: 'Details', controller: _body, maxLines: 6, hint: 'Share the details…'),
                const SizedBox(height: 16),
                Row(children: [
                  _decoChip('📷 Photo', c, () => showComingSoon(context, 'Photos')),
                  const SizedBox(width: 11),
                  _decoChip('📍 Location', c, () => showComingSoon(context, 'Location')),
                ]),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: PgPrimaryButton(label: _posting ? 'Posting…' : 'Post to community',
              onPressed: _posting ? () {} : _post),
          ),
        ]),
      ),
    );
  }

  Widget _decoChip(String label, PgColors c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(13)),
          child: Text(label, style: PgText.inter(13, FontWeight.w600, color: c.muted))),
      );
}
