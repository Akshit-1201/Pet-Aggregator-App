// Verifies the real Firebase repository implementations against the Firebase
// Local Emulator Suite (Auth + Firestore). Run with the emulators running:
//   firebase emulators:start --only auth,firestore --project pet-aggregator-app
//   flutter test integration_test/firebase_repos_test.dart -d emulator-5554
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firebase_auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_booking_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_booking_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_post_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_pro_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_swipe_repository.dart';
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

  testWidgets('swipes persist + reciprocal woof detected (real Firestore emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final swipes = FirestoreSwipeRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final me = await auth.signUp(email: 'sw_$stamp@x.com', password: 'secret1');
    await swipes.recordSwipe(Swipe(
        fromUid: me.uid, petId: 'pet_$stamp', ownerId: 'ownerX', direction: SwipeDirection.woof));
    final ids = await swipes.watchSwipedPetIds(me.uid).firstWhere((s) => s.contains('pet_$stamp'));
    expect(ids, contains('pet_$stamp'));

    // No reciprocity yet.
    expect(await swipes.hasReciprocalWoof(otherUid: 'ownerX', myUid: me.uid), isFalse);

    // ownerX (a second account) woofs one of my pets -> reciprocity.
    final other = await auth.signUp(email: 'ox_$stamp@x.com', password: 'secret1');
    await swipes.recordSwipe(Swipe(
        fromUid: other.uid, petId: 'mine_$stamp', ownerId: me.uid, direction: SwipeDirection.woof));
    expect(await swipes.hasReciprocalWoof(otherUid: other.uid, myUid: me.uid), isTrue);

    await auth.signOut();
  });

  testWidgets('pros upsert + watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final prosRepo = FirestoreProRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'pro_$stamp@x.com', password: 'secret1');

    await prosRepo.upsertPro(Pro(uid: me.uid, name: 'Aarav', area: 'Bandra West',
        bio: 'Walker', serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    final mine = await prosRepo.watchPro(me.uid).firstWhere((p) => p != null);
    expect(mine!.rate, 250);
    final all = await prosRepo.watchPros().firstWhere((l) => l.any((p) => p.uid == me.uid));
    expect(all.any((p) => p.name == 'Aarav'), isTrue);

    await auth.signOut();
  });

  testWidgets('bookings create + watchMyBookings round-trip (real Firestore emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final bookings = FirestoreBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'bk_$stamp@x.com', password: 'secret1');

    await bookings.createBooking(Booking(parentId: me.uid, proId: 'pro_$stamp', proName: 'Aarav',
        petId: 'pet_$stamp', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    final mine = await bookings.watchMyBookings(me.uid).firstWhere((l) => l.isNotEmpty);
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.total, 275);

    await auth.signOut();
  });

  testWidgets('homestays upsert + watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final homestaysRepo = FirestoreHomestayRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'host_$stamp@x.com', password: 'secret1');

    await homestaysRepo.upsertHomestay(Homestay(uid: me.uid, homeName: "Meera's Home",
        hostName: 'Meera Iyer', area: 'Bandra West', about: 'Spacious 2BHK.',
        homeType: HomeType.apartment, ratePerNight: 900, amenities: [Amenity.nearPark]));
    final mine = await homestaysRepo.watchHomestay(me.uid).firstWhere((h) => h != null);
    expect(mine!.ratePerNight, 900);
    expect(mine.verified, isFalse);
    expect(mine.amenities, contains(Amenity.nearPark));
    final all = await homestaysRepo.watchHomestays().firstWhere((l) => l.any((h) => h.uid == me.uid));
    expect(all.any((h) => h.homeName == "Meera's Home"), isTrue);

    await auth.signOut();
  });

  testWidgets('homestayBookings create + watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final repo = FirestoreHomestayBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'hb_$stamp@x.com', password: 'secret1');

    await repo.createHomestayBooking(HomestayBooking(guestId: me.uid, hostId: 'host_$stamp',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'pet_$stamp', petName: 'Bruno',
        ratePerNight: 900, checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, note: 'Friendly boy'));
    final mine = await repo.watchMyHomestayBookings(me.uid).firstWhere((l) => l.isNotEmpty);
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.total, 2850);
    expect(mine.single.status, 'requested');
    expect(mine.single.checkIn, DateTime(2026, 7, 12));

    await auth.signOut();
  });

  testWidgets('posts + comments create/watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final repo = FirestorePostRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'post_$stamp@x.com', password: 'secret1');

    final created = await repo.createPost(Post(authorId: me.uid, authorName: 'Radhika',
        category: PostCategory.health, title: 'Vet in Bandra?', body: 'Boosters due.', createdAt: stamp));
    expect(created.id, isNotEmpty);
    final posts = await repo.watchPosts().firstWhere((l) => l.any((p) => p.id == created.id));
    expect(posts.firstWhere((p) => p.id == created.id).title, 'Vet in Bandra?');

    await repo.addComment(created.id, Comment(authorId: me.uid, authorName: 'Radhika',
        body: 'Any tips?', createdAt: stamp + 1));
    final comments = await repo.watchComments(created.id).firstWhere((l) => l.isNotEmpty);
    expect(comments.single.body, 'Any tips?');
    final afterReply = await repo.watchPosts().firstWhere((l) =>
        l.any((p) => p.id == created.id && p.replyCount == 1));
    expect(afterReply.firstWhere((p) => p.id == created.id).replyCount, 1);

    await auth.signOut();
  });

  testWidgets('watchMyWoofCount reflects a recorded woof (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final swipes = FirestoreSwipeRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'woofc_$stamp@x.com', password: 'secret1');
    expect(await swipes.watchMyWoofCount(me.uid).first, 0);
    await swipes.recordSwipe(Swipe(fromUid: me.uid, petId: 'pet_$stamp', ownerId: 'owner_$stamp',
        direction: SwipeDirection.woof));
    final count = await swipes.watchMyWoofCount(me.uid).firstWhere((n) => n >= 1);
    expect(count, 1);
    await auth.signOut();
  });
}
