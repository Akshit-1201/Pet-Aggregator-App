import 'role.dart';

class UserProfile {
  final String uid, name, email, area;
  final Role role;
  final int notifsSeenAt;

  const UserProfile({
    required this.uid, required this.name, required this.email,
    required this.area, required this.role, this.notifsSeenAt = 0,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'area': area,
        'role': role.storageKey,
        'notifsSeenAt': notifsSeenAt,
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        role: Role.fromStorage((m['role'] ?? 'petParent') as String),
        notifsSeenAt: (m['notifsSeenAt'] ?? 0) as int,
      );

  UserProfile copyWith({String? area, int? notifsSeenAt}) => UserProfile(
        uid: uid, name: name, email: email, area: area ?? this.area, role: role,
        notifsSeenAt: notifsSeenAt ?? this.notifsSeenAt,
      );
}
