import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryProRepository upserts and streams pros', () async {
    final repo = InMemoryProRepository();
    expect(await repo.watchPros().first, isEmpty);
    await repo.upsertPro(const Pro(uid: 'u1', name: 'Aarav', area: 'Bandra West',
        bio: 'Walker', serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    expect((await repo.watchPros().first).single.name, 'Aarav');
    expect((await repo.watchPro('u1').first)!.rate, 250);
    // upsert overwrites the same uid.
    await repo.upsertPro(const Pro(uid: 'u1', name: 'Aarav', area: 'Khar',
        bio: 'Walker', serviceType: ServiceType.walker, rate: 300, experienceYears: 5));
    expect((await repo.watchPro('u1').first)!.rate, 300);
    expect((await repo.watchPros().first).length, 1);
  });
}
