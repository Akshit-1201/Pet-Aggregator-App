import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/notification_record.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('hasUnreadNotificationsProvider flips true -> mark-all-read -> false', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final notifications = FakeNotificationRepository([
      const NotificationRecord(id: 'n1', scenario: 'PAY1', category: 'money',
          title: 'Payment received', body: 'Dog walking with Rahul',
          route: '/payments', createdAt: 1000, read: false),
    ]);

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(notifications),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(notificationsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    expect(container.read(notificationsProvider).value?.length, 1);
    expect(container.read(hasUnreadNotificationsProvider), isTrue);

    await notifications.markAllRead(uid);
    await pumpEventQueue();

    expect(container.read(hasUnreadNotificationsProvider), isFalse);
  });
}
