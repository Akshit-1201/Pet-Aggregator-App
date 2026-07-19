import 'package:flutter/material.dart';
import '../../core/router/routes.dart';
import '../../data/models/booking.dart';
import '../../data/models/chat.dart';
import '../../data/models/homestay.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/pro.dart';
import '../../data/models/review.dart';

enum PgNotificationType { message, review, booking, homestay }

class NotificationItem {
  final PgNotificationType type;
  final String icon; // emoji
  final Color accent;
  final String title, body;
  final int timestamp; // millis — sort + unread
  final String? route; // deep-link target (null = non-navigating)
  final Object? extra;
  final bool read;

  const NotificationItem({
    required this.type, required this.icon, required this.accent,
    required this.title, required this.body, required this.timestamp,
    this.route, this.extra, this.read = false,
  });
}

int _eventTs(int updatedAt, int createdAt) => updatedAt > 0 ? updatedAt : createdAt;

/// Builds the derived notification feed (newest first) from the user's own data.
List<NotificationItem> buildNotifications({
  required String myUid,
  required int seenAt,
  required List<Chat> chats,
  required List<Review> reviews,
  required List<Booking> bookings,
  required List<HomestayBooking> homestays,
  List<Booking> receivedBookings = const [],
  List<HomestayBooking> receivedStays = const [],
  Pro? myPro,
  Homestay? myHomestay,
}) {
  bool unread(int ts) => ts > seenAt;
  final items = <NotificationItem>[];

  for (final c in chats) {
    if (!c.hasUnread(myUid)) continue;
    items.add(NotificationItem(
      type: PgNotificationType.message, icon: '💬', accent: const Color(0xFF6B8DE0),
      title: 'New message from ${c.otherName(myUid)}', body: c.lastMessage,
      timestamp: c.lastMessageAt, route: Routes.chat, extra: c, read: !unread(c.lastMessageAt)));
  }

  final (String? reviewRoute, Object? reviewExtra) = myPro != null
      ? (Routes.servicePro, myPro)
      : myHomestay != null
          ? (Routes.host, myHomestay)
          : (null, null);
  for (final r in reviews) {
    final stars = List.filled(r.stars.clamp(0, 5), '★').join();
    items.add(NotificationItem(
      type: PgNotificationType.review, icon: '⭐', accent: const Color(0xFFF59E2E),
      title: 'New review from ${r.authorName}',
      body: r.text.isEmpty ? stars : '$stars  ${r.text}',
      timestamp: r.createdAt, route: reviewRoute, extra: reviewExtra, read: !unread(r.createdAt)));
  }

  for (final b in bookings) {
    if (b.status == 'cancelled') continue;
    items.add(NotificationItem(
      type: PgNotificationType.booking, icon: '✅', accent: const Color(0xFF34B27B),
      title: 'Booking confirmed with ${b.proName}',
      body: '${b.serviceType.label} · ${b.dateLabel}',
      timestamp: b.createdAt, route: Routes.bookings, read: !unread(b.createdAt)));
  }

  for (final s in homestays) {
    items.add(NotificationItem(
      type: PgNotificationType.homestay, icon: '🏡', accent: const Color(0xFFF97316),
      title: 'Homestay request · ${s.petName}',
      body: '${s.homeName} · ${s.nights} nights',
      timestamp: s.createdAt, route: Routes.bookings, read: !unread(s.createdAt)));
  }

  for (final s in homestays) {
    if (s.status != 'accepted' && s.status != 'declined') continue;
    final ok = s.status == 'accepted';
    final ts = _eventTs(s.updatedAt, s.createdAt);
    items.add(NotificationItem(
        type: PgNotificationType.homestay,
        icon: ok ? '✅' : '❌',
        accent: ok ? const Color(0xFF34B27B) : const Color(0xFFE5484D),
        title: '${s.homeName} ${ok ? 'accepted' : 'declined'} your request',
        body: '${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights',
        timestamp: ts, route: Routes.bookings, extra: 0, read: !unread(ts)));
  }

  for (final s in receivedStays) {
    if (s.status == 'requested') {
      items.add(NotificationItem(
          type: PgNotificationType.homestay,
          icon: '🏡', accent: const Color(0xFFF97316),
          title: "New booking request from ${s.petName}'s parent",
          body: '${HomestayBooking.fmtDay(s.checkIn)} → ${HomestayBooking.fmtDay(s.checkOut)}'
              ' · ₹${s.total}',
          timestamp: s.createdAt, route: Routes.bookings, extra: 1,
          read: !unread(s.createdAt)));
    } else if (s.status == 'cancelled') {
      final ts = _eventTs(s.updatedAt, s.createdAt);
      items.add(NotificationItem(
          type: PgNotificationType.homestay,
          icon: '↩️', accent: const Color(0xFF9AA0A6),
          title: "${s.petName}'s stay was cancelled",
          body: '${s.homeName} · ${s.nights} nights',
          timestamp: ts, route: Routes.bookings, extra: 1, read: !unread(ts)));
    }
  }

  for (final b in receivedBookings) {
    if (b.status != 'cancelled') continue;
    final ts = _eventTs(b.updatedAt, b.createdAt);
    items.add(NotificationItem(
        type: PgNotificationType.booking,
        icon: '↩️', accent: const Color(0xFF9AA0A6),
        title: "${b.petName}'s booking was cancelled",
        body: '${b.serviceType.label} · ${b.dateLabel}',
        timestamp: ts, route: Routes.bookings, extra: 1, read: !unread(ts)));
  }

  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
}
