import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/legal/legal_links.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// "By continuing, you agree to our Terms & Conditions and Privacy Policy." —
/// both names open the document in-app. Pushed, so back returns to the form
/// with everything typed still there.
class LegalConsentLine extends StatefulWidget {
  const LegalConsentLine({super.key});

  @override
  State<LegalConsentLine> createState() => _LegalConsentLineState();
}

class _LegalConsentLineState extends State<LegalConsentLine> {
  late final _terms = TapGestureRecognizer()..onTap = () => context.push(Routes.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => context.push(Routes.privacyPolicy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final base = PgText.inter(12.5, FontWeight.w400, color: c.muted, height: 1.5);
    final link = PgText.inter(12.5, FontWeight.w700, color: c.brand, height: 1.5);
    return Text.rich(
      TextSpan(style: base, children: [
        const TextSpan(text: 'By continuing, you agree to our '),
        TextSpan(text: LegalDoc.terms.name, style: link, recognizer: _terms),
        const TextSpan(text: ' and '),
        TextSpan(text: LegalDoc.privacy.name, style: link, recognizer: _privacy),
        const TextSpan(text: '.'),
      ]),
      textAlign: TextAlign.center,
    );
  }
}
