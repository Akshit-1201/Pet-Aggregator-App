import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryHomestayRepository upserts and streams homestays', () async {
    final repo = InMemoryHomestayRepository();
    expect(await repo.watchHomestays().first, isEmpty);
    await repo.upsertHomestay(const Homestay(uid: 'u1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', area: 'Bandra West', about: 'x',
        homeType: HomeType.apartment, ratePerNight: 900));
    expect((await repo.watchHomestays().first).single.homeName, "Meera's Home");
    expect((await repo.watchHomestay('u1').first)!.ratePerNight, 900);
    // upsert overwrites the same uid.
    await repo.upsertHomestay(const Homestay(uid: 'u1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', area: 'Khar', about: 'x',
        homeType: HomeType.villa, ratePerNight: 1100));
    expect((await repo.watchHomestay('u1').first)!.ratePerNight, 1100);
    expect((await repo.watchHomestays().first).length, 1);
  });
}
