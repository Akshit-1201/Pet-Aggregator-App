import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
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
  Uint8List? _photo;
  bool _posting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (bytes != null && mounted) setState(() => _photo = bytes);
    } catch (_) {
      if (mounted) showPgSnack(context, "Couldn't open your photos. Please try again.");
    }
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
    try {
      final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;

      // Upload before creating the post. A post referencing an image that never
      // uploaded would render a permanent broken slot; posting without the
      // photo is the better failure.
      var photoUrl = '';
      if (_photo != null) {
        try {
          photoUrl = await ref.read(storageRepositoryProvider).uploadImage(
                path: 'posts/${me.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg',
                bytes: _photo!,
              );
        } catch (_) {
          if (mounted) showPgSnack(context, "Couldn't upload the photo — posting without it.");
        }
      }

      final created = await ref.read(postRepositoryProvider).createPost(Post(
          authorId: me.uid, authorName: profile?.name ?? 'Someone', category: _category,
          title: title, body: _body.text.trim(), photoUrl: photoUrl,
          area: profile?.area ?? '',
          createdAt: DateTime.now().millisecondsSinceEpoch));
      if (mounted) context.go(Routes.postLive, extra: created);
    } catch (_) {
      if (mounted) {
        setState(() {
          _posting = false;
          _error = "Couldn't post that. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // Rebuilds this subtree whenever a tracked controller changes, so
    // PopScope's canPop (baked in at build time) reflects the current dirty
    // state — plain text edits otherwise never trigger a rebuild here, since
    // PgTextField has no onChanged wired to setState. _photo doesn't need
    // this: every assignment to it already goes through setState.
    return ListenableBuilder(
      listenable: Listenable.merge([_title, _body]),
      builder: (context, _) => PgBackScope(
        // The expensive case here is the attached photo — picked but not yet
        // uploaded, so a stray back press loses it with nothing to restore.
        confirmWhen: () =>
            _photo != null ||
            _title.text.trim().isNotEmpty ||
            _body.text.trim().isNotEmpty,
        confirmMessage: "This post isn't published yet. Leaving now discards it.",
        child: Scaffold(
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
                      _decoChip(_photo == null ? '📷 Photo' : '📷 Change photo', c, _pickPhoto),
                      if (_photo != null) ...[
                        const SizedBox(width: 11),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_photo!, width: 44, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                  width: 44, height: 44, color: c.surface2,
                                  child: Icon(Icons.broken_image_outlined,
                                      color: c.muted, size: 18)))),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _photo = null),
                          behavior: HitTestBehavior.opaque,
                          child: Text('Remove',
                              style: PgText.inter(12.5, FontWeight.w700, color: c.heart))),
                      ],
                    ]),
                    // The prototype's "📍 Location" chip is gone: there is no
                    // per-post location to set. The author's area is attached
                    // automatically instead, which is the information that chip
                    // implied and is genuinely useful on Lost & Found.
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
        ),
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
