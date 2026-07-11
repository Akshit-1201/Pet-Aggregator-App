import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/services/booking_confirmed_screen.dart';
import '../support/pump.dart';

const _booking = Booking(id: 'b1', parentId: 'u1', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');

void main() {
  testWidgets('shows the confirmation summary; Message hints coming soon', (tester) async {
    await pumpPg(tester, const BookingConfirmedScreen(booking: _booking));
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
    expect(find.textContaining('Aarav'), findsWidgets);
    expect(find.textContaining('Bruno'), findsWidgets);
    await tester.tap(find.textContaining('Message'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
