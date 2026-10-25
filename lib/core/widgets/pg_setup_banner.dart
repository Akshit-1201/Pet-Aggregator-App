import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// "You have no listing yet" prompt at the top of a list, for a partner who
/// signed up with that role but hasn't created their listing.
class PgSetupBanner extends StatelessWidget {
  final String emoji, title, subtitle;
  final VoidCallback onTap;
  const PgSetupBanner({super.key, required this.emoji, required this.title,
      required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
            Text(subtitle, style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          Icon(Icons.chevron_right, color: c.brand),
        ]),
      ),
    );
  }
}
