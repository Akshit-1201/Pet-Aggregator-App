import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_swipe_card.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import '../../support/pump.dart';

PetProfile _pet() => PetProfile(
    id: 'p1', ownerId: 'B', name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
    sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
    accentColor: PetProfile.accentFor('Bruno'));

void main() {
  testWidgets('drag right past threshold fires onWoof', (tester) async {
    var woofed = false, passed = false;
    await pumpPg(tester, PgSwipeCard(pet: _pet(), onWoof: () => woofed = true, onPass: () => passed = true));
    await tester.drag(find.byType(PgSwipeCard), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(woofed, isTrue);
    expect(passed, isFalse);
  });

  testWidgets('drag left past threshold fires onPass', (tester) async {
    var woofed = false, passed = false;
    await pumpPg(tester, PgSwipeCard(pet: _pet(), onWoof: () => woofed = true, onPass: () => passed = true));
    await tester.drag(find.byType(PgSwipeCard), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(passed, isTrue);
    expect(woofed, isFalse);
  });

  testWidgets('small drag springs back, fires nothing', (tester) async {
    var woofed = false, passed = false;
    await pumpPg(tester, PgSwipeCard(pet: _pet(), onWoof: () => woofed = true, onPass: () => passed = true));
    await tester.drag(find.byType(PgSwipeCard), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(woofed, isFalse);
    expect(passed, isFalse);
  });
}
