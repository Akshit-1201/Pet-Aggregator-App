import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PASTE THE HOSTED DOCUMENT LINKS HERE. Nothing else needs to change: Settings
// and sign-up already link to these, and the in-app viewer loads whatever URL
// is set. While a link is empty the viewer shows "…will be published here
// soon" instead of a broken page.
//
// Any public https page works — a Google Doc published to the web
// (File → Share → Publish to web), a Notion page, or your own site.
// ─────────────────────────────────────────────────────────────────────────────
const privacyPolicyUrl = '';
const termsUrl = '';

enum LegalDoc {
  privacy('Privacy policy', 'Privacy Policy'),
  terms('Terms & conditions', 'Terms & Conditions');

  /// [title] heads the viewer and labels the Settings row; [name] is how the
  /// document is referred to inside a sentence.
  final String title, name;
  const LegalDoc(this.title, this.name);
}

/// Behind a provider so tests can supply URLs without editing the constants.
final legalUrlsProvider = Provider<Map<LegalDoc, String>>((_) => const {
      LegalDoc.privacy: privacyPolicyUrl,
      LegalDoc.terms: termsUrl,
    });
