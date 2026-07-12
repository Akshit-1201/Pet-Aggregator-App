import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/features/homestay/host_accepted_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the request-sent summary; Message hints coming soon', (tester) async {
    final b = HomestayBooking(guestId: 'g1', hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
        subtotal: 2700, fee: 150, total: 2850);
    await pumpPg(tester, HostAcceptedScreen(booking: b));
    expect(find.text('Request sent! 🎉'), findsOneWidget);
    expect(find.textContaining('Bruno'), findsOneWidget);
    expect(find.textContaining('3 nights · ₹2850'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    await tester.tap(find.textContaining('Message Meera'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
