import 'role.dart';

/// Which push categories a user wants. Read server-side by `notify()` before
/// every push, so turning one off stops the notification at the source rather
/// than hiding it after delivery.
///
/// All five default to **true**, including when the field is absent — existing
/// accounts predate these flags and must not silently go quiet.
///
/// There is deliberately no flag for money or account notifications. Those are
/// the essential tier: a refund that landed or an ID check that failed is a
/// support incident if it goes unsaid, not a preference. Email is likewise
/// never gated — a receipt is a record, not an interruption.
class NotificationPrefs {
  final bool messages, bookings, woofs, community, reminders;
  const NotificationPrefs({
    this.messages = true,
    this.bookings = true,
    this.woofs = true,
    this.community = true,
    this.reminders = true,
  });

  NotificationPrefs copyWith({
    bool? messages, bool? bookings, bool? woofs, bool? community, bool? reminders,
  }) =>
      NotificationPrefs(
        messages: messages ?? this.messages,
        bookings: bookings ?? this.bookings,
        woofs: woofs ?? this.woofs,
        community: community ?? this.community,
        reminders: reminders ?? this.reminders,
      );

  Map<String, dynamic> toMap() => {
        'notifyMessages': messages,
        'notifyBookings': bookings,
        'notifyWoofs': woofs,
        'notifyCommunity': community,
        'notifyReminders': reminders,
      };

  factory NotificationPrefs.fromMap(Map<String, dynamic> m) => NotificationPrefs(
        messages: (m['notifyMessages'] ?? true) as bool,
        bookings: (m['notifyBookings'] ?? true) as bool,
        woofs: (m['notifyWoofs'] ?? true) as bool,
        community: (m['notifyCommunity'] ?? true) as bool,
        reminders: (m['notifyReminders'] ?? true) as bool,
      );
}

class UserProfile {
  final String uid, name, email, area, photoUrl;
  final Role role;
  final NotificationPrefs notify;

  const UserProfile({
    required this.uid, required this.name, required this.email,
    required this.area, required this.role,
    this.photoUrl = '', this.notify = const NotificationPrefs(),
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'area': area,
        'role': role.storageKey,
        'photoUrl': photoUrl,
        ...notify.toMap(),
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        role: Role.fromStorage((m['role'] ?? 'petParent') as String),
        photoUrl: (m['photoUrl'] ?? '') as String,
        notify: NotificationPrefs.fromMap(m),
      );

  UserProfile copyWith({
    String? area, String? photoUrl, NotificationPrefs? notify,
  }) =>
      UserProfile(
        uid: uid, name: name, email: email, area: area ?? this.area, role: role,
        photoUrl: photoUrl ?? this.photoUrl,
        notify: notify ?? this.notify,
      );
}
