import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/availability.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/booking_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

Future<FakeAuthRepository> _pump(WidgetTester tester,
    {Pro pro = _pro, InMemoryBookingRepository? bookings, bool withPet = true}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    petRepositoryProvider.overrideWithValue(
        withPet ? InMemoryPetRepository(fixturePets('uid_me@x.com')) : InMemoryPetRepository()),
    bookingRepositoryProvider.overrideWithValue(bookings ?? InMemoryBookingRepository()),
    paymentServiceProvider.overrideWithValue(FakePaymentService.success()),
  ], initialLocation: Routes.booking, extra: pro);
  await tester.pumpAndSettle();
  return auth;
}

Booking _confirmedAt(int startMin, DateTime day, {String id = 'other', int duration = 60}) =>
    Booking(id: id, parentId: 'someone-else', proId: 'pro1', proName: 'Aarav Sharma',
        petId: 'x', petName: 'X', serviceType: ServiceType.walker, rate: 250, fee: 25,
        total: 275, dateLabel: '', timeSlot: formatMinutes(startMin), status: 'confirmed',
        date: Booking.isoDate(day), startMin: startMin, durationMin: duration);

void main() {
  testWidgets('renders total and the pet; Continue needs a time first', (tester) async {
    await _pump(tester);
    expect(find.text('Bruno'), findsOneWidget);          // first of the user's pets
    expect(find.textContaining('275'), findsWidgets);    // total = 250 + 25
    expect(find.text('Pick a time to continue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slot-540')));
    await tester.pumpAndSettle();
    expect(find.text('Continue to payment'), findsOneWidget);
  });

  testWidgets('with no pets, prompts to add one', (tester) async {
    await _pump(tester, withPet: false);
    expect(find.text('Add a pet to book'), findsOneWidget);
  });

  // The old screen offered the same three hard-coded times for everyone.
  testWidgets("slots come from the pro's own hours and slot length", (tester) async {
    final tomorrow = _day(1);
    final pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4,
        availability: Availability(
            weekly: {tomorrow.weekday: const [TimeRange(540, 660)]}, // 9-11 AM only
            slotMinutes: 30));
    await _pump(tester, pro: pro);
    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();

    for (final t in ['9:00 AM', '9:30 AM', '10:00 AM', '10:30 AM']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('11:00 AM'), findsNothing); // a 30-min slot at 11 would end past 11
    expect(find.text('8:00 AM'), findsNothing);
    expect(find.text('30 min walk'), findsOneWidget);
  });

  testWidgets("a day the pro doesn't work says so and offers no times", (tester) async {
    final tomorrow = _day(1);
    final pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4,
        availability: Availability(weekly: {
          for (var d = 1; d <= 7; d++)
            if (d != tomorrow.weekday) d: const [TimeRange(540, 600)],
        }, slotMinutes: 60));
    await _pump(tester, pro: pro);
    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining("doesn't take bookings on this day"), findsOneWidget);
    expect(find.byKey(const Key('slot-540')), findsNothing);
  });

  // The client's requirement: a time the pro is already booked for must not be
  // bookable again.
  testWidgets('a time already booked with the pro is shown taken and cannot be picked',
      (tester) async {
    final bookings = InMemoryBookingRepository([_confirmedAt(540, _day(1))]);
    await _pump(tester, bookings: bookings);
    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('slot-540')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a time to continue'), findsOneWidget); // tap did nothing

    await tester.tap(find.byKey(const Key('slot-600')));
    await tester.pumpAndSettle();
    expect(find.text('Continue to payment'), findsOneWidget);
  });

  testWidgets('a longer booking blocks every slot it overlaps', (tester) async {
    // A 2h booking at 9:00 must block 9:00 and 10:00 but not 11:00.
    final bookings = InMemoryBookingRepository([_confirmedAt(540, _day(1), duration: 120)]);
    await _pump(tester, bookings: bookings);
    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();

    for (final m in [540, 600]) {
      await tester.tap(find.byKey(Key('slot-$m')));
      await tester.pumpAndSettle();
      expect(find.text('Pick a time to continue'), findsOneWidget, reason: '$m');
    }
    await tester.tap(find.byKey(const Key('slot-660')));
    await tester.pumpAndSettle();
    expect(find.text('Continue to payment'), findsOneWidget);
  });

  testWidgets('a time someone else books while you look at it is unpicked live',
      (tester) async {
    final bookings = InMemoryBookingRepository();
    await _pump(tester, bookings: bookings);
    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slot-540')));
    await tester.pumpAndSettle();
    expect(find.text('Continue to payment'), findsOneWidget);

    bookings.seedConfirmed(_confirmedAt(540, _day(1), id: 'rival'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a time to continue'), findsOneWidget);
  });

  testWidgets('a hold that loses the race cancels the new booking and says so', (tester) async {
    final bookings = _RacingBookingRepository();
    final auth = await _pump(tester, bookings: bookings);
    await tester.tap(find.byKey(const Key('booking-day-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slot-540')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue to payment'));
    await tester.tap(find.text('Continue to payment'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Someone just booked 9:00 AM'), findsOneWidget);
    expect(find.text('Select date'), findsOneWidget); // still on the picker, not payment
    final mine = await bookings.watchMyBookings(auth.currentUser!.uid).first;
    expect(mine.single.status, 'cancelled');
  });
}

/// A repository whose hold always loses, as if another customer's request
/// committed a moment earlier.
class _RacingBookingRepository extends InMemoryBookingRepository {
  @override
  Future<void> holdSlot(String bookingId) async => throw const SlotTakenException();
}
