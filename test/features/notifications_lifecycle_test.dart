// test/features/notifications_lifecycle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/notifications/notification_item.dart';

Booking _svc({String status = 'confirmed', int createdAt = 10, int updatedAt = 0}) => Booking(
    id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x', petName: 'Bruno',
    serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275, dateLabel: 'Tue',
    timeSlot: '5:00 PM', status: status, createdAt: createdAt, updatedAt: updatedAt);

HomestayBooking _stay({String status = 'requested', int createdAt = 10, int updatedAt = 0}) =>
    HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: "Meera's Home",
        hostName: 'Meera', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2027, 1, 10), checkOut: DateTime(2027, 1, 13), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, status: status,
        createdAt: createdAt, updatedAt: updatedAt);

List<NotificationItem> _build({List<Booking> bookings = const [],
        List<HomestayBooking> homestays = const [],
        List<Booking> receivedBookings = const [],
        List<HomestayBooking> receivedStays = const [],
        int seenAt = 0}) =>
    buildNotifications(myUid: 'me', seenAt: seenAt, chats: const [], reviews: const [],
        bookings: bookings, homestays: homestays,
        receivedBookings: receivedBookings, receivedStays: receivedStays);

void main() {
  test('host sees a new-request item deep-linking to the Received tab', () {
    final items = _build(receivedStays: [_stay(createdAt: 100)]);
    final item = items.singleWhere((n) => n.title.startsWith('New booking request'));
    expect(item.title, "New booking request from Bruno's parent");
    expect(item.route, Routes.bookings);
    expect(item.extra, 1);
    expect(item.timestamp, 100);
    expect(item.read, isFalse);
  });

  test('guest sees accepted/declined items stamped with updatedAt', () {
    final acc = _build(homestays: [_stay(status: 'accepted', updatedAt: 200)]);
    final item = acc.singleWhere((n) => n.title.contains('accepted'));
    expect(item.title, "Meera's Home accepted your request");
    expect(item.timestamp, 200);
    expect(item.extra, 0);

    final dec = _build(homestays: [_stay(status: 'declined', updatedAt: 300)]);
    expect(dec.singleWhere((n) => n.title.contains('declined')).timestamp, 300);
  });

  test('a decided item with updatedAt 0 falls back to createdAt', () {
    final items = _build(homestays: [_stay(status: 'accepted', createdAt: 40, updatedAt: 0)]);
    expect(items.singleWhere((n) => n.title.contains('accepted')).timestamp, 40);
  });

  test('supply side sees cancellation items', () {
    final items = _build(
        receivedStays: [_stay(status: 'cancelled', updatedAt: 500)],
        receivedBookings: [_svc(status: 'cancelled', updatedAt: 600)]);
    expect(items.singleWhere((n) => n.title == "Bruno's stay was cancelled").timestamp, 500);
    expect(items.singleWhere((n) => n.title == "Bruno's booking was cancelled").timestamp, 600);
  });

  test('a cancelled service booking no longer claims "Booking confirmed"', () {
    final items = _build(bookings: [_svc(status: 'cancelled')]);
    expect(items.where((n) => n.title.startsWith('Booking confirmed')), isEmpty);
  });
}
