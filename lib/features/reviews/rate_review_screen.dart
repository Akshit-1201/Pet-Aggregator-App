import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';

class RateReviewScreen extends ConsumerStatefulWidget {
  final ReviewTarget? target;
  const RateReviewScreen({super.key, this.target});
  @override
  ConsumerState<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends ConsumerState<RateReviewScreen> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _submitting = false;

  static const _captions = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(ReviewTarget target, String myUid) async {
    if (_stars < 1 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final profile = await ref.read(userRepositoryProvider).watchUser(myUid).first;
      await ref.read(reviewRepositoryProvider).submitReview(Review(
          targetType: target.type, targetId: target.id, targetName: target.name,
          authorId: myUid, authorName: profile?.name ?? 'Someone', bookingId: target.bookingId,
          stars: _stars, text: _comment.text.trim(),
          createdAt: DateTime.now().millisecondsSinceEpoch));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (context.canPop()) context.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Thanks! Your review is live ⭐'),
          behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not submit your review. Please try again.'),
          behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final target = widget.target;
    if (target == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nothing to review')));
    }
    final myUid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final canSubmit = _stars >= 1 && !_submitting;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: PgAppBar(
              title: 'Rate your ${target.type == ReviewTargetType.homestay ? 'stay' : 'booking'}',
              onBack: () => PgBackScope.pop(context)),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
            children: [
              Center(child: Column(children: [
                const PgImageSlot(size: 84, circle: true, emoji: '🧑'),
                const SizedBox(height: 13),
                Text(target.name, textAlign: TextAlign.center,
                  style: PgText.poppins(19, FontWeight.w800, color: c.text)),
                const SizedBox(height: 3),
                Text(target.subtitle, textAlign: TextAlign.center,
                  style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => setState(() => _stars = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Opacity(
                          opacity: i <= _stars ? 1 : 0.3,
                          child: const Text('⭐', style: TextStyle(fontSize: 40)))),
                    ),
                ]),
                const SizedBox(height: 6),
                Text(_captions[_stars], style: PgText.inter(13.5, FontWeight.w700, color: c.brand)),
              ])),
              const SizedBox(height: 22),
              PgTextField(label: 'Add a comment (optional)', controller: _comment,
                hint: 'Share how it went…', maxLines: 4),
            ],
          )),
          Container(
            padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: GestureDetector(
              onTap: canSubmit ? () => _submit(target, myUid) : null,
              child: Opacity(
                opacity: canSubmit ? 1 : 0.5,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]),
                    borderRadius: BorderRadius.circular(16)),
                  child: Text('Submit review', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)))),
            ),
          ),
        ]),
      ),
    );
  }
}
