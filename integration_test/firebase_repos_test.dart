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
import 'package:pet_aggregator_app/data/models/chat.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firebase_auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_booking_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_chat_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_booking_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_post_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_pro_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_review_repository.dart';
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
    expect(mine.single.createdAt, greaterThan(0)); // client-int createdAt stamped on create

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

  testWidgets('chats + messages open/send/watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final repo = FirestoreChatRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'chat_$stamp@x.com', password: 'secret1');
    final otherUid = 'other_$stamp';

    final chat = await repo.openChat(myUid: me.uid, myName: 'Me', otherUid: otherUid, otherName: 'Aarav');
    expect(chat.id, Chat.chatIdFor(me.uid, otherUid));
    final mine = await repo.watchMyChats(me.uid).firstWhere((l) => l.any((c) => c.id == chat.id));
    expect(mine.any((c) => c.id == chat.id), isTrue);

    await repo.sendMessage(chatId: chat.id, senderId: me.uid, text: 'ring me 9876543210');
    final msgs = await repo.watchMessages(chat.id).firstWhere((l) => l.isNotEmpty);
    expect(msgs.single.text, 'ring me ••••'); // write-time masked
    final afterSend = await repo.watchMyChats(me.uid).firstWhere((l) =>
        l.any((c) => c.id == chat.id && c.lastMessage == 'ring me ••••'));
    expect(afterSend.firstWhere((c) => c.id == chat.id).lastMessage, 'ring me ••••');

    await repo.markRead(chatId: chat.id, uid: me.uid);
    final read = await repo.watchMyChats(me.uid).firstWhere((l) =>
        l.any((c) => c.id == chat.id && (c.lastRead[me.uid] ?? 0) > 0));
    expect((read.firstWhere((c) => c.id == chat.id).lastRead[me.uid] ?? 0) > 0, isTrue);

    await auth.signOut();
  });

  testWidgets('reviews submit + aggregate transactionally + idempotent (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final pros = FirestoreProRepository();
    final reviews = FirestoreReviewRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // The pro owns their listing doc (rules require uid == doc id to create it).
    final proAcct = await auth.signUp(email: 'proacct_$stamp@x.com', password: 'secret1');
    await pros.upsertPro(Pro(uid: proAcct.uid, name: 'Aarav', area: 'Bandra West', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    await auth.signOut();

    // A different user (the reviewer) rates a booking with this pro.
    final me = await auth.signUp(email: 'rev_$stamp@x.com', password: 'secret1');
    Review review(int stars) => Review(targetType: ReviewTargetType.pro, targetId: proAcct.uid,
        targetName: 'Aarav', authorId: me.uid, authorName: 'Radhika', bookingId: 'bk_$stamp',
        stars: stars, text: 'Great', createdAt: stamp);

    await reviews.submitReview(review(5));
    final list = await reviews.watchReviews(proAcct.uid).firstWhere((l) => l.isNotEmpty);
    expect(list.single.stars, 5);
    final after = await pros.watchPro(proAcct.uid).firstWhere((p) => p != null && p.reviewCount == 1);
    expect(after!.reviewCount, 1);
    expect(after.rating, 5.0);
    expect(await reviews.watchMyReviewedBookingIds(me.uid).firstWhere((s) => s.isNotEmpty),
        contains('bk_$stamp'));

    // Re-submitting the same booking is a no-op (transaction sees the existing review).
    await reviews.submitReview(review(1));
    final again = await pros.watchPro(proAcct.uid).first;
    expect(again!.reviewCount, 1); // unchanged

    await auth.signOut();
  });

  testWidgets('booking lifecycle transitions obey the rules matrix (real Firestore emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final stays = FirestoreHomestayBookingRepository();
    final bookings = FirestoreBookingRepository();
    final db = FirebaseFirestore.instance;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final host = await auth.signUp(email: 'lh_$stamp@x.com', password: 'secret1');
    await auth.signOut();
    final guest = await auth.signUp(email: 'lg_$stamp@x.com', password: 'secret1');

    // Guest requests a stay with the host.
    await stays.createHomestayBooking(HomestayBooking(guestId: guest.uid, hostId: host.uid,
        homeName: 'H', hostName: 'M', petId: 'p', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2027, 1, 10), checkOut: DateTime(2027, 1, 13), nights: 3,
        subtotal: 2700, fee: 150, total: 2850));
    final stayId =
        (await stays.watchMyHomestayBookings(guest.uid).firstWhere((l) => l.isNotEmpty)).single.id;

    // Guest cannot accept their own request.
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'accepted', 'updatedAt': 1}),
        throwsA(isA<FirebaseException>()));

    // A valid transition that also touches another field is denied (hasOnly guard).
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update(
            {'status': 'accepted', 'total': 1, 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));

    // Host accepts via the repo (writes status + updatedAt only).
    await auth.signOut();
    await auth.signIn(email: 'lh_$stamp@x.com', password: 'secret1');
    await stays.acceptRequest(stayId);
    final accepted = (await stays.watchBookingsForHost(host.uid).firstWhere(
            (l) => l.any((s) => s.id == stayId && s.status == 'accepted')))
        .firstWhere((s) => s.id == stayId);
    expect(accepted.updatedAt, greaterThan(0));

    // Host cannot re-decide, cancel, or touch other fields once decided.
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'declined', 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'cancelled', 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'total': 1, 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));

    // Guest can cancel the accepted stay.
    await auth.signOut();
    await auth.signIn(email: 'lg_$stamp@x.com', password: 'secret1');
    await stays.cancelStay(stayId);
    final cancelled = await stays
        .watchMyHomestayBookings(guest.uid)
        .firstWhere((l) => l.any((s) => s.id == stayId && s.status == 'cancelled'));
    expect(cancelled.firstWhere((s) => s.id == stayId).status, 'cancelled');

    // Service booking: parent cancels; pro-side stream sees it; invalid targets rejected.
    await bookings.createBooking(Booking(parentId: guest.uid, proId: host.uid, proName: 'Aarav',
        petId: 'p', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
        total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', date: '2027-01-10'));
    final bkId = (await bookings.watchMyBookings(guest.uid).firstWhere((l) => l.isNotEmpty)).single.id;
    await expectLater(
        db.collection('bookings').doc(bkId).update({'status': 'paused', 'updatedAt': 1}),
        throwsA(isA<FirebaseException>()));

    // Valid parent cancel + an extra field is denied (hasOnly guard).
    await expectLater(
        db.collection('bookings').doc(bkId).update(
            {'status': 'cancelled', 'total': 1, 'updatedAt': 1}),
        throwsA(isA<FirebaseException>()));

    await bookings.cancelBooking(bkId);

    await auth.signOut();
    await auth.signIn(email: 'lh_$stamp@x.com', password: 'secret1');
    final proSide = await bookings.watchBookingsForPro(host.uid).firstWhere((l) => l.isNotEmpty);
    expect(proSide.single.status, 'cancelled');
    // The pro cannot resurrect a cancelled booking.
    await expectLater(
        db.collection('bookings').doc(bkId).update({'status': 'confirmed', 'updatedAt': 9}),
        throwsA(isA<FirebaseException>()));

    await auth.signOut();
  });
}
