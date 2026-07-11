import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryBookingRepository creates and streams my bookings', () async {
    final repo = InMemoryBookingRepository();
    expect(await repo.watchMyBookings('u1').first, isEmpty);
    await repo.createBooking(const Booking(parentId: 'u1', proId: 'p1', proName: 'Aarav',
        petId: 'pet1', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    // Another parent's booking is not mine.
    await repo.createBooking(const Booking(parentId: 'other', proId: 'p1', proName: 'Aarav',
        petId: 'x', petName: 'Y', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Wed', timeSlot: '8:00 AM'));
    final mine = await repo.watchMyBookings('u1').first;
    expect(mine.length, 1);
    expect(mine.single.petName, 'Bruno');
  });
}
