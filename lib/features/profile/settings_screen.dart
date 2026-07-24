import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_toggle.dart';
import '../../data/repositories/providers.dart';
import 'delete_account_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        PgAppBar(title: 'Settings', onBack: () => context.pop()),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 30), children: [
          _label(context, 'APPEARANCE'),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🌙', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dark mode', style: PgText.inter(14, FontWeight.w600, color: c.text)),
                Text('Easier on the eyes at night', style: PgText.inter(12, FontWeight.w400, color: c.muted)),
              ])),
              PgToggle(value: isDark, onChanged: (v) => ref.read(themeModeProvider.notifier).toggleDark(v)),
            ]),
          ),
          const SizedBox(height: 18),
          _label(context, 'PRIVACY & SAFETY'),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _navRow(context, c, '🚫', 'Blocked users',
                  'People you have hidden across Pawgo',
                  () => context.push(Routes.blockedUsers), border: true),
              // Google Play requires an in-app deletion path for any app that
              // lets you create an account.
              _navRow(context, c, '🗑️', 'Delete account',
                  'Permanently remove your account and data',
                  () => showDeleteAccountFlow(context, ref), danger: true),
            ]),
          ),
          const SizedBox(height: 18),
          _label(context, 'ABOUT'),
          _staticRow(c, 'About Pawgo', 'v1.0.0'),
        ])),
      ])),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 9, top: 2),
        child: Text(text, style: PgText.inter(12, FontWeight.w700, color: context.pg.faint)),
      );

  Widget _navRow(BuildContext context, PgColors c, String emoji, String title,
          String subtitle, VoidCallback onTap,
          {bool border = false, bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              border: border ? Border(bottom: BorderSide(color: c.border)) : null),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: PgText.inter(14, FontWeight.w600, color: danger ? c.heart : c.text)),
              Text(subtitle, style: PgText.inter(12, FontWeight.w400, color: c.muted)),
            ])),
            Icon(Icons.chevron_right, color: c.faint, size: 20),
          ]),
        ),
      );

  Widget _staticRow(PgColors c, String title, String trailing) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Text(title, style: PgText.inter(14, FontWeight.w600, color: c.text))),
          Text(trailing, style: PgText.inter(12, FontWeight.w400, color: c.faint)),
        ]),
      );
}
