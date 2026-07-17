import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Host-accepted "Message" opens a conversation', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    final booking = HomestayBooking(guestId: auth.currentUser!.uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno',
        ratePerNight: 900, checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23),
        nights: 3, subtotal: 2700, fee: 150, total: 2850);

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.hostAccepted, extra: booking);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message Meera'));
    await tester.pumpAndSettle();
    expect(find.text('Meera Iyer'), findsOneWidget);   // conversation header
    expect(find.text('Message…'), findsOneWidget);     // composer hint
  });
}
