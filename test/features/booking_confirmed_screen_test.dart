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
  _verbs();
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

// Seen on device: the sentence used the service's NAME as a verb —
// "Aarav will dog walker Bruno on…".
void _verbs() {
  final cases = {
    ServiceType.walker: 'Aarav will walk Bruno on Tue 15 Jul, 5:00 PM.',
    ServiceType.sitter: 'Aarav will look after Bruno on Tue 15 Jul, 5:00 PM.',
    ServiceType.groomer: 'Aarav will groom Bruno on Tue 15 Jul, 5:00 PM.',
    ServiceType.trainer: 'Aarav will train Bruno on Tue 15 Jul, 5:00 PM.',
  };
  for (final MapEntry(key: type, value: sentence) in cases.entries) {
    testWidgets('the summary reads naturally for a ${type.label}', (tester) async {
      final auth = FakeAuthRepository();
      await auth.signUp(email: 'me@x.com', password: 'secret1');
      await pumpPgApp(tester, overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
        chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      ], initialLocation: Routes.bookingConfirmed, extra: Booking(id: 'b1', parentId: 'u1',
          proId: 'pro1', proName: 'Aarav Sharma', petId: 'p1', petName: 'Bruno',
          serviceType: type, rate: 250, fee: 25, total: 275,
          dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
      await tester.pumpAndSettle();
      expect(find.textContaining(sentence), findsOneWidget);
    });
  }
}
