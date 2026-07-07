import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_choice_card.dart';
import 'package:pet_aggregator_app/core/widgets/pg_page_dots.dart';
import 'package:pet_aggregator_app/core/widgets/pg_app_bar.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('PgChoiceCard fires onTap and shows title', (tester) async {
    var tapped = false;
    await pumpPg(tester, PgChoiceCard(
      emoji: '🐾', title: 'Pet Parent', subtitle: 'Discover, book, board & chat',
      selected: true, onTap: () => tapped = true));
    expect(find.text('Pet Parent'), findsOneWidget);
    await tester.tap(find.text('Pet Parent'));
    expect(tapped, isTrue);
  });

  testWidgets('PgPageDots renders `count` dots', (tester) async {
    await pumpPg(tester, const PgPageDots(count: 4, index: 0));
    expect(find.byKey(const ValueKey('pg-dot')), findsNWidgets(4));
  });

  testWidgets('PgAppBar shows title and back button', (tester) async {
    await pumpPg(tester, PgAppBar(title: 'Add your pet', onBack: () {}));
    expect(find.text('Add your pet'), findsOneWidget);
  });
}
