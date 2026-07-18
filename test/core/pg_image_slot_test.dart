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
}
