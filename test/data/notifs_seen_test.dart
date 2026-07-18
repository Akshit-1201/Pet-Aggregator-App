// test/data/notifs_seen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import '../support/fakes.dart';

void main() {
  test('UserProfile.notifsSeenAt round-trips', () {
    const u = UserProfile(uid: 'me', name: 'Radhika', email: 'r@x.com', area: 'Bandra',
        role: Role.petParent, notifsSeenAt: 99);
    expect(UserProfile.fromMap('me', u.toMap()).notifsSeenAt, 99);
    expect(const UserProfile(uid: 'me', name: 'R', email: 'e', area: 'a', role: Role.petParent).notifsSeenAt, 0);
  });

  test('markNotificationsSeen sets notifsSeenAt + re-emits', () async {
    final repo = InMemoryUserRepository();
    await repo.createUser(const UserProfile(uid: 'me', name: 'R', email: 'e', area: 'a', role: Role.petParent));
    expect((await repo.watchUser('me').first)!.notifsSeenAt, 0);
    await repo.markNotificationsSeen('me');
    expect((await repo.watchUser('me').first)!.notifsSeenAt, greaterThan(0));
  });
}
