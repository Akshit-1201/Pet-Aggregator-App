import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/notification_record.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

NotificationRecord _rec(String id,
        {String title = 'Payment received',
        String category = 'money',
        bool read = false,
        int createdAt = 1000}) =>
    NotificationRecord(
      id: id, scenario: 'PAY1', category: category, title: title,
      body: 'Dog walking with Rahul', route: '/payments',
      createdAt: createdAt, read: read);

/// Notifications is a protected route (see `_protected` in app_router.dart),
/// so every test here needs a signed-in user or the router bounces to Welcome
/// before the screen — and NotificationsScreen itself reads `myUid` off
/// authRepositoryProvider — before it ever gets to the repository override.
Future<FakeAuthRepository> _signedInAuth() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

void main() {
  testWidgets('renders records from the repository', (t) async {
    final auth = await _signedInAuth();
    final repo = FakeNotificationRepository([_rec('a'), _rec('b', title: 'Refunded')]);
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.notifications, providesNotificationRepository: true);
    await t.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets('shows the empty state when there is nothing', (t) async {
    final auth = await _signedInAuth();
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(FakeNotificationRepository()),
    ], initialLocation: Routes.notifications, providesNotificationRepository: true);
    await t.pumpAndSettle();
    expect(find.textContaining("You're all caught up"), findsOneWidget);
  });

  testWidgets('email-only scenarios still appear in the feed', (t) async {
    final auth = await _signedInAuth();
    final repo = FakeNotificationRepository([
      _rec('c', title: 'Stay request sent', category: 'bookings'),
    ]);
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.notifications, providesNotificationRepository: true);
    await t.pumpAndSettle();
    expect(find.text('Stay request sent'), findsOneWidget);
  });

  testWidgets('Mark all read hides the affordance and clears unread', (t) async {
    final auth = await _signedInAuth();
    final repo = FakeNotificationRepository([_rec('a'), _rec('b', title: 'Refunded')]);
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.notifications, providesNotificationRepository: true);
    await t.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
    await t.tap(find.text('Mark all read'));
    await t.pumpAndSettle();
    expect(repo.records.every((r) => r.read), isTrue);
    expect(find.text('Mark all read'), findsNothing);
    // Marking read re-styles the row (surface instead of brandSoft) — it must
    // not remove the item from the feed, the way the old seenAt cursor never did.
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets('no Mark all read affordance when everything is read', (t) async {
    final auth = await _signedInAuth();
    final repo = FakeNotificationRepository([_rec('a', read: true)]);
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.notifications, providesNotificationRepository: true);
    await t.pumpAndSettle();
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('tapping an unread row marks it read and navigates to its route', (t) async {
    final auth = await _signedInAuth();
    final repo = FakeNotificationRepository([_rec('a')]);
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      notificationRepositoryProvider.overrideWithValue(repo),
      // The row's onTap navigates via context.go(item.route) to /payments,
      // which reads these two directly (not defaulted by pumpPgApp).
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
    ], initialLocation: Routes.notifications, providesNotificationRepository: true);
    await t.pumpAndSettle();

    expect(repo.records.single.read, isFalse);
    await t.tap(find.text('Payment received'));
    await t.pumpAndSettle();

    expect(repo.records.single.read, isTrue);
    expect(find.text('Payments'), findsOneWidget); // landed on /payments
  });
}
