import 'role.dart';

/// Which push categories a user wants. Read server-side by `sendPushTo` before
/// every send, so turning one off stops the notification at the source rather
/// than hiding it after delivery.
///
/// All three default to **true**, including when the field is absent — existing
/// accounts predate these flags and must not silently go quiet.
class NotificationPrefs {
  final bool messages, bookings, woofs;
  const NotificationPrefs({
    this.messages = true,
    this.bookings = true,
    this.woofs = true,
  });

  NotificationPrefs copyWith({bool? messages, bool? bookings, bool? woofs}) =>
      NotificationPrefs(
        messages: messages ?? this.messages,
        bookings: bookings ?? this.bookings,
        woofs: woofs ?? this.woofs,
      );

  Map<String, dynamic> toMap() => {
        'notifyMessages': messages,
        'notifyBookings': bookings,
        'notifyWoofs': woofs,
      };

  factory NotificationPrefs.fromMap(Map<String, dynamic> m) => NotificationPrefs(
        messages: (m['notifyMessages'] ?? true) as bool,
        bookings: (m['notifyBookings'] ?? true) as bool,
        woofs: (m['notifyWoofs'] ?? true) as bool,
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
