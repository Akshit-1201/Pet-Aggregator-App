// test/features/notifications_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/chat.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/features/notifications/notification_item.dart';

void main() {
  test('buildNotifications maps sources, sorts newest-first, flags read + deep-links', () {
    const chat = Chat(id: 'c1', participants: ['me', 'a'], names: {'me': 'Me', 'a': 'Aarav'},
        lastMessage: 'hi there', lastSenderId: 'a', lastMessageAt: 300, lastRead: {'me': 0});
    const review = Review(targetType: ReviewTargetType.pro, targetId: 'me', targetName: 'Me',
        authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 5, text: 'great', createdAt: 200);
    const booking = Booking(id: 'bk1', parentId: 'me', proId: 'p', proName: 'Aarav', petId: 'x',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', createdAt: 100);

    final items = buildNotifications(myUid: 'me', seenAt: 150, chats: const [chat],
        reviews: const [review], bookings: const [booking], homestays: const []);

    expect(items.map((i) => i.type).toList(),
        [PgNotificationType.message, PgNotificationType.review, PgNotificationType.booking]); // 300,200,100
    expect(items[0].title, 'New message from Aarav');
    expect(items[0].route, Routes.chat);
    expect(items[0].read, isFalse);            // 300 > 150
    expect(items[1].route, isNull);            // review, no myPro/myHomestay -> no deep-link
    expect(items.last.read, isTrue);           // booking 100 <= 150
    expect(items.last.route, Routes.bookings);
  });

  test('review deep-links to my Pro profile when I have one; a read chat is excluded', () {
    const chatRead = Chat(id: 'c1', participants: ['me', 'a'], names: {'me': 'Me', 'a': 'A'},
        lastMessage: 'hi', lastSenderId: 'a', lastMessageAt: 100, lastRead: {'me': 500}); // read
    const review = Review(targetType: ReviewTargetType.pro, targetId: 'me', targetName: 'Me',
        authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 4, text: '', createdAt: 200);
    const pro = Pro(uid: 'me', name: 'Me', area: 'Bandra', bio: 'b', serviceType: ServiceType.walker,
        rate: 250, experienceYears: 3);

    final items = buildNotifications(myUid: 'me', seenAt: 0, chats: const [chatRead],
        reviews: const [review], bookings: const [], homestays: const [], myPro: pro);
    expect(items.length, 1);                    // read chat excluded
    expect(items.single.type, PgNotificationType.review);
    expect(items.single.route, Routes.servicePro);
    expect(items.single.extra, pro);
  });
}
