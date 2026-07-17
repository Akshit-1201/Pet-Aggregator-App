import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart'; // reuse Post.timeAgo
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';

/// The list of reviews for a pro/host, or "No reviews yet." when empty.
class ReviewsSection extends ConsumerWidget {
  final String targetId;
  const ReviewsSection({super.key, required this.targetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final reviews = ref.watch(reviewsProvider(targetId)).value ?? const <Review>[];
    if (reviews.isEmpty) {
      return Text('No reviews yet.', style: PgText.inter(13.5, FontWeight.w400, color: c.muted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final r in reviews) _ReviewTile(review: r)]);
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(review.authorName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.poppins(13.5, FontWeight.w700, color: c.text))),
          Text(List.filled(review.stars.clamp(0, 5), '★').join(),
            style: PgText.inter(12.5, FontWeight.w700, color: c.brand)),
        ]),
        if (review.text.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(review.text, style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.45)),
        ],
        const SizedBox(height: 5),
        Text(Post.timeAgo(review.createdAt), style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]),
    );
  }
}
