// Verifies the real Firebase repository implementations against the Firebase
// Local Emulator Suite (Auth + Firestore). Run with the emulators running:
//   firebase emulators:start --only auth,firestore --project pet-aggregator-app
//   flutter test integration_test/firebase_repos_test.dart -d emulator-5554
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firebase_auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_user_repository.dart';
import 'package:pet_aggregator_app/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // The Android emulator reaches the host loopback via 10.0.2.2.
    await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);
  });

  testWidgets('sign up -> profile -> pet -> live streams (real Firebase emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final users = FirestoreUserRepository();
    final pets = FirestorePetRepository();

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'itest_$stamp@x.com';

    // Sign up creates a real auth user.
    final me = await auth.signUp(email: email, password: 'secret1');
    expect(me.uid, isNotEmpty);
    expect(auth.currentUser?.uid, me.uid);

    // Profile persists + area update round-trips through Firestore.
    await users.createUser(UserProfile(
        uid: me.uid, name: 'Radhika Nair', email: email, area: '', role: Role.petParent));
    await users.updateArea(me.uid, 'Bandra West');
    final profile = await users.watchUser(me.uid).firstWhere((u) => u?.area == 'Bandra West');
    expect(profile!.name, 'Radhika Nair');
    expect(profile.role, Role.petParent);

    // Own pet persists and appears in watchMyPets.
    await pets.addPet(PetProfile(
        id: '', ownerId: me.uid, name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
        accentColor: PetProfile.accentFor('Bruno')));
    final mine = await pets.watchMyPets(me.uid).firstWhere((l) => l.isNotEmpty);
    expect(mine.single.name, 'Bruno');
    expect(mine.single.ownerId, me.uid);
    expect(mine.single.species, Species.dog);

    // A second account's pet shows up in "nearby" (which excludes the current user).
    final other = await auth.signUp(email: 'other_$stamp@x.com', password: 'secret1');
    await pets.addPet(PetProfile(
        id: '', ownerId: other.uid, name: 'Mochi', breed: 'Persian cat', ageLabel: '1 yr',
        sex: 'female', area: 'Khar', species: Species.cat, vaccinated: true,
        accentColor: PetProfile.accentFor('Mochi')));
    final nearby = await pets
        .watchNearbyPets(excludeOwnerId: me.uid)
        .firstWhere((l) => l.any((p) => p.name == 'Mochi'));
    expect(nearby.any((p) => p.ownerId == me.uid), isFalse);

    await auth.signOut();
    expect(auth.currentUser, isNull);
  });
}
