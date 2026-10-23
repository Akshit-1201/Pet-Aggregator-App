// Owner request (2026-10-23): Privacy Policy + Terms & Conditions links that
// open inside the app, with the back gesture and button working properly.
// Spec: docs/superpowers/specs/2026-10-23-pawgo-legal-documents-design.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/legal/legal_links.dart';
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/home/home_screen.dart';
import 'package:pet_aggregator_app/features/legal/document_view.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _privacyUrl = 'https://example.com/privacy';
const _termsUrl = 'https://example.com/terms';

Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

/// Every view the screen creates, newest last.
final _views = <FakeDocumentView>[];

List<Override> _overrides(FakeAuthRepository auth, {bool withUrls = true}) => [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      legalUrlsProvider.overrideWithValue(withUrls
          ? const {LegalDoc.privacy: _privacyUrl, LegalDoc.terms: _termsUrl}
          : const {LegalDoc.privacy: '', LegalDoc.terms: ''}),
      documentViewFactoryProvider.overrideWithValue((url, events) {
        final v = FakeDocumentView(url, events);
        _views.add(v);
        return v;
      }),
    ];

/// Settings, then the named row — the real way in for a signed-in user.
Future<void> _openFromSettings(WidgetTester t, String row, {bool withUrls = true}) async {
  await pumpPgApp(t, overrides: _overrides(await _signedIn(), withUrls: withUrls),
      initialLocation: Routes.settings);
  await t.pumpAndSettle();
  await t.dragUntilVisible(find.text(row), find.byType(Scrollable).first, const Offset(0, -200));
  await t.pumpAndSettle();
  await t.tap(find.text(row));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    _views.clear();
    PgExitConfirm.reset();
  });

  group('Settings → ABOUT', () {
    testWidgets('Privacy policy opens the policy inside the app', (t) async {
      await _openFromSettings(t, 'Privacy policy');
      expect(find.text('PAGE $_privacyUrl'), findsOneWidget);
      expect(_views.single.url, _privacyUrl);
    });

    testWidgets('Terms & conditions opens the terms inside the app', (t) async {
      await _openFromSettings(t, 'Terms & conditions');
      expect(find.text('PAGE $_termsUrl'), findsOneWidget);
    });

    testWidgets('the back chevron returns to Settings', (t) async {
      await _openFromSettings(t, 'Privacy policy');
      await t.tap(find.byIcon(Icons.chevron_left).first);
      await t.pumpAndSettle();
      expect(find.text('Terms & conditions'), findsOneWidget); // Settings again
      expect(find.text('PAGE $_privacyUrl'), findsNothing);
    });

    testWidgets('system back (button or gesture) returns to Settings', (t) async {
      await _openFromSettings(t, 'Terms & conditions');
      await _systemBack(t);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('PAGE $_termsUrl'), findsNothing);
    });
  });

  group('links inside the document', () {
    testWidgets('system back steps back through them before leaving', (t) async {
      await _openFromSettings(t, 'Privacy policy');
      _views.single.followLink('https://example.com/cookies');
      await t.pumpAndSettle();
      expect(find.text('PAGE https://example.com/cookies'), findsOneWidget);

      await _systemBack(t);
      expect(find.text('PAGE $_privacyUrl'), findsOneWidget,
          reason: 'back should return to the policy, not close it');

      await _systemBack(t);
      expect(find.text('Terms & conditions'), findsOneWidget); // left to Settings
    });

    testWidgets('the chevron follows the same rule', (t) async {
      await _openFromSettings(t, 'Privacy policy');
      _views.single.followLink('https://example.com/cookies');
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.chevron_left).first);
      await t.pumpAndSettle();
      expect(find.text('PAGE $_privacyUrl'), findsOneWidget);

      await t.tap(find.byIcon(Icons.chevron_left).first);
      await t.pumpAndSettle();
      expect(find.text('Terms & conditions'), findsOneWidget);
    });
  });

  testWidgets('before the links are added: a "coming soon" note, and back still works',
      (t) async {
    await _openFromSettings(t, 'Privacy policy', withUrls: false);
    expect(find.textContaining('will be published here soon'), findsOneWidget);
    expect(_views, isEmpty, reason: 'nothing to load, so no WebView');

    await _systemBack(t);
    expect(find.text('Terms & conditions'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and Retry tries again', (t) async {
    await _openFromSettings(t, 'Privacy policy');
    _views.single.failLoad();
    await t.pumpAndSettle();
    expect(find.textContaining("Couldn't load"), findsOneWidget);

    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(_views.single.retries, 1);
    expect(find.textContaining("Couldn't load"), findsNothing);
    expect(find.text('PAGE $_privacyUrl'), findsOneWidget);
  });

  testWidgets('opened with nothing beneath it (deep link): back goes Home, not out of the app',
      (t) async {
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpPgApp(t, overrides: _overrides(await _signedIn()),
        initialLocation: Routes.terms);
    await t.pumpAndSettle();
    await _systemBack(t);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isFalse);
  });

  // handlePopRoute() bypasses the engine. On a phone, back only reaches Dart
  // if the engine was told the framework handles it — see home_shell_back_test.
  testWidgets('the engine is told the framework handles back while a link is open',
      (t) async {
    final handlesBack = <bool>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (c) async {
      if (c.method == 'SystemNavigator.setFrameworkHandlesBack') {
        handlesBack.add(c.arguments as bool);
      }
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await t.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/lifecycle',
        const StringCodec().encodeMessage('AppLifecycleState.resumed'), (_) {});

    await _openFromSettings(t, 'Privacy policy');
    _views.single.followLink('https://example.com/cookies');
    await t.pumpAndSettle();

    expect(handlesBack, isNotEmpty);
    expect(handlesBack.last, isTrue);
  });

  group('sign-up', () {
    Future<FakeAuthRepository> openSignup(WidgetTester t) async {
      final auth = FakeAuthRepository();
      await pumpPgApp(t, overrides: _overrides(auth), initialLocation: Routes.signup);
      await t.pumpAndSettle();
      return auth;
    }

    Future<void> tapLink(WidgetTester t, String text) async {
      await t.dragUntilVisible(find.textContaining('you agree to our'),
          find.byType(Scrollable).first, const Offset(0, -200));
      await t.pumpAndSettle();
      await t.tapOnText(find.textRange.ofSubstring(text));
      await t.pumpAndSettle();
    }

    testWidgets('states that continuing means agreeing to both documents', (t) async {
      await openSignup(t);
      expect(find.textContaining('By continuing, you agree to our Terms & Conditions and '
          'Privacy Policy'), findsOneWidget);
    });

    testWidgets('each document opens from its link', (t) async {
      await openSignup(t);
      await tapLink(t, 'Terms & Conditions');
      expect(find.text('PAGE $_termsUrl'), findsOneWidget);
      await _systemBack(t);

      await tapLink(t, 'Privacy Policy');
      expect(find.text('PAGE $_privacyUrl'), findsOneWidget);
    });

    testWidgets('back returns to the form with what was typed still there', (t) async {
      await openSignup(t);
      await t.enterText(find.byType(TextField).first, 'Meera Iyer');
      await tapLink(t, 'Privacy Policy');

      await _systemBack(t);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Meera Iyer'), findsOneWidget);
    });
  });
}
