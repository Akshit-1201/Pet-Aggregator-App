import 'package:flutter/material.dart';

/// One server-authored notification, read from `notifications/{uid}/items`.
///
/// The server stores the rendered `title`/`body` rather than parameters — the
/// catalogue in `functions/src/notify/catalog.ts` is the single source of copy,
/// so the client never re-renders text and the two can never drift.
///
/// Presentation is NOT stored: emoji and accent are derived from `category`
/// here. Putting `0xFF34B27B` in Firestore would be a category error.
class NotificationRecord {
  final String id, scenario, category, title, body, route;
  final int createdAt;
  final bool read;

  const NotificationRecord({
    required this.id, required this.scenario, required this.category,
    required this.title, required this.body, required this.route,
    required this.createdAt, required this.read,
  });

  /// Every field falls back rather than throwing — a single malformed or
  /// partial document (missing fields, or a field of the wrong type) must
  /// not break the rest of the feed, since all docs in a snapshot are mapped
  /// together.
  factory NotificationRecord.fromMap(String id, Map<String, dynamic> m) =>
      NotificationRecord(
        id: id,
        scenario: _str(m['scenario']),
        category: _str(m['category']),
        title: _str(m['title']),
        body: _str(m['body']),
        route: _str(m['route']),
        createdAt: _int(m['createdAt']),
        read: _bool(m['read']),
      );

  static String _str(dynamic v) => v is String ? v : '';
  static int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
  static bool _bool(dynamic v) => v is bool ? v : false;

  static const _emoji = {
    'messages': '💬', 'bookings': '🗓️', 'woofs': '🐾', 'community': '💬',
    'reminders': '⏰', 'money': '💰', 'account': '✅',
  };

  static const _accent = {
    'messages': Color(0xFF6B8DE0), 'bookings': Color(0xFF34B27B),
    'woofs': Color(0xFFF59E2E), 'community': Color(0xFF8B5CF6),
    'reminders': Color(0xFFF97316), 'money': Color(0xFF34B27B),
    'account': Color(0xFF34B27B),
  };

  /// Falls back to a bell/neutral grey for a category the installed app
  /// doesn't recognise — the server's category list can grow ahead of the app.
  String get emoji => _emoji[category] ?? '🔔';
  Color get accent => _accent[category] ?? const Color(0xFF9AA0A6);
}
