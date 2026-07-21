import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/features/notifications/notification_item.dart';

HomestayBooking _stay({required String status, int createdAt = 10, int updatedAt = 0}) =>
    HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: "Meera's Home", hostName: 'Meera',
        petId: 'x', petName: 'Bruno', ratePerNight: 900, checkIn: DateTime(2027, 1, 10),
        checkOut: DateTime(2027, 1, 13), nights: 3, subtotal: 2700, fee: 150, total: 2850,
        status: status, createdAt: createdAt, updatedAt: updatedAt);

void main() {
  test('host sees a confirmed-and-paid item for a paid received stay', () {
    final items = buildNotifications(myUid: 'h', seenAt: 0, chats: const [], reviews: const [],
        bookings: const [], homestays: const [],
        receivedStays: [_stay(status: 'paid', updatedAt: 500)]);
    final item = items.singleWhere((n) => n.title.contains('confirmed & paid'));
    expect(item.title, "Bruno's stay is confirmed & paid");
    expect(item.timestamp, 500);
    expect(item.route, Routes.bookings);
    expect(item.extra, 1);
    expect(item.read, isFalse);
  });

  test('a non-paid received stay produces no confirmed-and-paid item', () {
    final items = buildNotifications(myUid: 'h', seenAt: 0, chats: const [], reviews: const [],
        bookings: const [], homestays: const [],
        receivedStays: [_stay(status: 'accepted', updatedAt: 500)]);
    expect(items.where((n) => n.title.contains('confirmed & paid')), isEmpty);
  });
}
