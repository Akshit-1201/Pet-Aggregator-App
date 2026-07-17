import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _booking = Booking(id: 'b1', parentId: 'u1', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');

void main() {
  testWidgets('shows the confirmation summary; Message opens a conversation', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.bookingConfirmed, extra: _booking);
    await tester.pumpAndSettle();

    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
    expect(find.textContaining('Aarav'), findsWidgets);
    expect(find.textContaining('Bruno'), findsWidgets);

    await tester.tap(find.text('Message Aarav'));
    await tester.pumpAndSettle();
    expect(find.text('Aarav Sharma'), findsOneWidget); // conversation header
    expect(find.text('Message…'), findsOneWidget);     // composer hint
  });
}
