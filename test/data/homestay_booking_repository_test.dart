import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import '../support/fakes.dart';

HomestayBooking _b(String guestId, String petName) => HomestayBooking(
    guestId: guestId, hostId: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    petId: 'p_$petName', petName: petName, ratePerNight: 900,
    checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
    subtotal: 2700, fee: 150, total: 2850);

void main() {
  test('InMemoryHomestayBookingRepository creates and streams my bookings', () async {
    final repo = InMemoryHomestayBookingRepository();
    expect(await repo.watchMyHomestayBookings('g1').first, isEmpty);
    await repo.createHomestayBooking(_b('g1', 'Bruno'));
    await repo.createHomestayBooking(_b('g2', 'Mochi')); // another guest's — not mine
    final mine = await repo.watchMyHomestayBookings('g1').first;
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.total, 2850);
    expect(mine.single.status, 'requested');
  });
}
