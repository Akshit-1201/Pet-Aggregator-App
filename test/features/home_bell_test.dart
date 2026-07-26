// test/features/home_bell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/notification_record.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Home bell shows an unread dot and opens Notifications', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    // Unread state now lives in the server-written notifications feed, not a
    // profile timestamp — seed it via the repository instead.
    final notifications = FakeNotificationRepository([
      const NotificationRecord(id: 'n1', scenario: 'PAY1', category: 'money',
          title: 'Payment received', body: 'Dog walking with Rahul',
          route: '/payments', createdAt: 1000, read: false),
    ]);

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      notificationRepositoryProvider.overrideWithValue(notifications),
    ], initialLocation: Routes.home, providesNotificationRepository: true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notif-dot')), findsOneWidget); // unread notification
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
