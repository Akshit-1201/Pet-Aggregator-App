import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the request-sent summary', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final b = HomestayBooking(guestId: auth.currentUser!.uid, hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
        subtotal: 2700, fee: 150, total: 2850);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
    ], initialLocation: Routes.hostAccepted, extra: b);
    await tester.pumpAndSettle();

    expect(find.text('Request sent! 🎉'), findsOneWidget);
    expect(find.textContaining('Bruno'), findsOneWidget);
    expect(find.textContaining('3 nights · ₹2850'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    expect(find.text('Message Meera'), findsOneWidget); // Message→conversation covered by message_button_nav_test
  });
}
