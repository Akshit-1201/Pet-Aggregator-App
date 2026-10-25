import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('filling the form and saving writes a pro listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Aarav Sharma',
        email: 'me@x.com', area: 'Bandra West', role: Role.servicePro));
    final pros = InMemoryProRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(pros),
    ], initialLocation: Routes.proSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '250'); // rate
    await tester.enterText(find.byType(TextField).at(1), '4');   // experience
    await tester.enterText(find.byType(TextField).at(2), 'Friendly walker'); // bio
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    final mine = await pros.watchPro(auth.currentUser!.uid).first;
    expect(mine!.name, 'Aarav Sharma');
    expect(mine.rate, 250);
    expect(mine.area, 'Bandra West');
  });

  testWidgets("the pro's weekly hours and slot length are saved with the listing",
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Aarav Sharma',
        email: 'me@x.com', area: 'Bandra West', role: Role.servicePro));
    final pros = InMemoryProRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(pros),
    ], initialLocation: Routes.proSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '250');
    await tester.ensureVisible(find.byKey(const Key('slot-length-30')));
    await tester.tap(find.byKey(const Key('slot-length-30')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('avail-7-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('avail-7-toggle'))); // Sundays off
    await tester.pumpAndSettle();
    expect(find.text('Not working'), findsOneWidget);
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    final mine = (await pros.watchPro(auth.currentUser!.uid).first)!;
    expect(mine.availability.slotMinutes, 30);
    expect(mine.availability.rangesFor(7), isEmpty);
    expect(mine.availability.rangesFor(1), isNotEmpty);
  });

  testWidgets('saving with every day off is refused with a reason', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pros = InMemoryProRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      proRepositoryProvider.overrideWithValue(pros),
    ], initialLocation: Routes.proSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '250');
    for (var d = 1; d <= 7; d++) {
      await tester.ensureVisible(find.byKey(Key('avail-$d-toggle')));
      await tester.tap(find.byKey(Key('avail-$d-toggle')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    expect(find.textContaining('at least one day'), findsOneWidget);
    expect(await pros.watchPro(auth.currentUser!.uid).first, isNull);
  });

  testWidgets('a behaviourist picks specialties; other types never show them', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Kavya Rao',
        email: 'me@x.com', area: 'Bandra West', role: Role.servicePro));
    final pros = InMemoryProRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(pros),
    ], initialLocation: Routes.proSetup);
    await tester.pumpAndSettle();

    expect(find.text('Specialties'), findsNothing); // Walker by default
    await tester.tap(find.text('🧠 Pet Behaviourist'));
    await tester.pumpAndSettle();
    expect(find.text('Specialties'), findsOneWidget);
    expect(find.text('Rate (₹ per consult)'), findsOneWidget);
    await tester.tap(find.text('Anxiety'));
    await tester.tap(find.text('Puppies'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '1500');
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    final mine = await pros.watchPro(auth.currentUser!.uid).first;
    expect(mine!.serviceType, ServiceType.behaviourist);
    expect(mine.specialties, [Specialty.anxiety, Specialty.puppies]);
  });
}
