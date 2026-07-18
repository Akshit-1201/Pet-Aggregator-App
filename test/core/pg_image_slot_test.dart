import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders a network image when imageUrl is set', (tester) async {
    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾', imageUrl: 'https://x/img.jpg'));
    expect(
      find.byWidgetPredicate((w) =>
          w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == 'https://x/img.jpg'),
      findsOneWidget,
    );
  });

  testWidgets('renders the emoji placeholder when imageUrl is null or empty', (tester) async {
    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾'));
    expect(find.text('🐾'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾', imageUrl: ''));
    expect(find.text('🐾'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('fills its bounded parent when size is null', (tester) async {
    await pumpPg(
      tester,
      const SizedBox(
        width: 200,
        height: 300,
        child: PgImageSlot(imageUrl: 'https://x/img.jpg'),
      ),
    );
    // PgImageSlot always draws a 1px `Border.all` around its content; Container
    // auto-applies a border's `dimensions` as padding to its child so the
    // border isn't painted over the image. So the fully-filled Image is the
    // 200x300 parent box minus that 1px inset on every side (198x298), not
    // exactly 200x300 — this proves the image fills 100% of the *available*
    // content area rather than collapsing to its intrinsic (zero) size.
    expect(tester.getSize(find.byType(Image)), const Size(198, 298));
  });
}
