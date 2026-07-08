import 'role.dart';

class UserProfile {
  final String uid, name, email, area;
  final Role role;

  const UserProfile({
    required this.uid, required this.name, required this.email,
    required this.area, required this.role,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'area': area,
        'role': role.storageKey,
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        role: Role.fromStorage((m['role'] ?? 'petParent') as String),
      );

  UserProfile copyWith({String? area}) => UserProfile(
        uid: uid, name: name, email: email, area: area ?? this.area, role: role,
      );
}
