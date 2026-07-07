import 'role.dart';

class UserProfile {
  final String name, phone, area;
  final Role role;
  const UserProfile({
    required this.name, required this.phone, required this.area, required this.role,
  });
}
