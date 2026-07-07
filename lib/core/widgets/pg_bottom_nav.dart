import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class PgBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const PgBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.explore_rounded, label: 'Discover'),
    (icon: Icons.pets_rounded, label: 'Services'),
    (icon: Icons.forum_rounded, label: 'Community'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (i) {
          final active = i == currentIndex;
          final color = active ? c.brand : c.faint;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_items[i].icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(_items[i].label, style: PgText.inter(10.5, FontWeight.w600, color: color)),
            ]),
          );
        }),
      ),
    );
  }
}
