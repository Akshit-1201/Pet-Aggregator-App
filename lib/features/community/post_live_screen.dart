import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/post.dart';

class PostLiveScreen extends StatelessWidget {
  final Post? post;
  const PostLiveScreen({super.key, this.post});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final p = post;
    if (p == null) {
      return PgBackScope(
        upTo: Routes.community,
        child: Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('No post')),
        ),
      );
    }
    return PgBackScope(
      upTo: Routes.community,
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
            child: Column(
              children: [
                // Terminal screen: upTo: Routes.community is the declared
                // destination. Builder gives the chevron a context INSIDE
                // PgBackScope's subtree — the outer `context` above is an
                // ancestor of it and would silently degrade to a plain pop.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Builder(builder: (ctx) => GestureDetector(
                    onTap: () => PgBackScope.pop(ctx),
                    child: Container(
                      width: 42, height: 42, alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface, border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(PgRadius.iconBtn)),
                      child: Icon(Icons.chevron_left, color: c.text)),
                  )),
                ),
                const Spacer(),
                Container(
                  width: 108,
                  height: 108,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0x1F6B8DE0),
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    width: 78,
                    height: 78,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF9DB6EC), Color(0xFF6B8DE0)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('💬', style: TextStyle(fontSize: 34)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Your post is live! 🎉',
                  textAlign: TextAlign.center,
                  style: PgText.poppins(
                    25,
                    FontWeight.w800,
                    color: c.text,
                    ls: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Pet parents near you can now see and reply.',
                  textAlign: TextAlign.center,
                  style: PgText.inter(
                    14.5,
                    FontWeight.w400,
                    color: c.muted,
                    height: 1.55,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () => context.go(Routes.thread, extra: p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.brand, c.brand2]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'View my post',
                        style: PgText.poppins(
                          15.5,
                          FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => context.go(Routes.community),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Back to community',
                      style: PgText.inter(14, FontWeight.w600, color: c.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
