// integration_test/functions_test.dart
//
// Verifies the payment callables against the Functions emulator. Run with:
//   npm --prefix functions run build
//   firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
//   flutter test integration_test/functions_test.dart -d emulator-5554
// Requires functions/.secret.local containing RAZORPAY_KEY_SECRET=test_secret
// (git-ignored; recreate on a fresh clone).
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firebase_auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_booking_repository.dart';
import 'package:pet_aggregator_app/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
    FirebaseFunctions.instanceFor(region: 'asia-south1')
        .useFunctionsEmulator('10.0.2.2', 5001);
    FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);
  });

  testWidgets('verifyBookingPayment: auth gate, valid HMAC accepted, tampering rejected',
      (tester) async {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Unauthenticated calls are rejected by both callables.
    await expectLater(
        fns.httpsCallable('verifyBookingPayment')
            .call({'orderId': 'o', 'paymentId': 'p', 'signature': 's'}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'unauthenticated')));
    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'amountRupees': 275}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'unauthenticated')));

    await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: 'fn_$stamp@x.com', password: 'secret1');

    // A valid signature (dummy secret matches functions/.secret.local).
    const secret = 'test_secret';
    const orderId = 'order_test1';
    const paymentId = 'pay_test1';
    final valid = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$orderId|$paymentId'))
        .toString();
    final ok = await fns.httpsCallable('verifyBookingPayment').call<Map<Object?, Object?>>(
        {'orderId': orderId, 'paymentId': paymentId, 'signature': valid});
    expect(ok.data['verified'], true);

    // A tampered signature is rejected.
    final tampered = valid.replaceRange(0, 1, valid[0] == 'a' ? 'b' : 'a');
    await expectLater(
        fns.httpsCallable('verifyBookingPayment')
            .call({'orderId': orderId, 'paymentId': paymentId, 'signature': tampered}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'permission-denied')));

    // createBookingOrder input validation (no Razorpay network needed to reject).
    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'amountRupees': 0}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'invalid-argument')));

    await FirebaseAuth.instance.signOut();
  });

  testWidgets('refundBookingPayment: auth + precondition gates, then 0-refund cancel + idempotency',
      (tester) async {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final auth = FirebaseAuthRepository();
    final stays = FirestoreHomestayBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Unauthenticated -> rejected.
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': 'x'}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'unauthenticated')));

    final guest = await auth.signUp(email: 'rf_$stamp@x.com', password: 'secret1');

    // Missing/unknown booking.
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': ''}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'invalid-argument')));
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': 'nope_$stamp'}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'not-found')));

    // A requested (unpaid) booking owned by the guest -> not-paid.
    await stays.createHomestayBooking(HomestayBooking(guestId: guest.uid, hostId: 'host_$stamp',
        homeName: 'H', hostName: 'M', petId: 'p', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime.now().add(const Duration(days: 1)),
        checkOut: DateTime.now().add(const Duration(days: 4)), nights: 3,
        subtotal: 2700, fee: 150, total: 2850));
    final reqId = (await stays.watchMyHomestayBookings(guest.uid).firstWhere((l) => l.isNotEmpty)).single.id;
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': reqId}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.message, 'message', 'not-paid')));

    // Drive it to paid (checkIn ~12h away -> the 0-refund path): host accepts, guest pays.
    await auth.signOut();
    final host = await auth.signUp(email: 'rfh_$stamp@x.com', password: 'secret1');
    // Re-point the booking's host to this account so acceptRequest passes rules:
    // create a fresh booking whose hostId is this host, then run accept+pay.
    await auth.signOut();
    await auth.signIn(email: 'rf_$stamp@x.com', password: 'secret1');
    await stays.createHomestayBooking(HomestayBooking(guestId: guest.uid, hostId: host.uid,
        homeName: 'H2', hostName: 'M', petId: 'p', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime.now().add(const Duration(days: 1)),
        checkOut: DateTime.now().add(const Duration(days: 4)), nights: 3,
        subtotal: 2700, fee: 150, total: 2850));
    final payId = (await stays.watchMyHomestayBookings(guest.uid)
        .firstWhere((l) => l.any((s) => s.hostId == host.uid))).firstWhere((s) => s.hostId == host.uid).id;
    await auth.signOut();
    await auth.signIn(email: 'rfh_$stamp@x.com', password: 'secret1');
    await stays.acceptRequest(payId);
    await auth.signOut();
    await auth.signIn(email: 'rf_$stamp@x.com', password: 'secret1');
    await stays.markPaid(payId, 'pay_rf_$stamp');

    // The host must NOT be able to refund the guest's booking (admin-privileged
    // function — this guest-ownership check is the only barrier).
    await auth.signOut();
    await auth.signIn(email: 'rfh_$stamp@x.com', password: 'secret1');
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': payId}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'permission-denied')));
    await auth.signOut();
    await auth.signIn(email: 'rf_$stamp@x.com', password: 'secret1');

    // Guest cancels < 24h out -> 0 refund, no Razorpay call, booking cancelled.
    final res = await fns.httpsCallable('refundBookingPayment').call<Map<Object?, Object?>>({'bookingId': payId});
    expect(res.data['refundAmount'], 0);
    expect(res.data['refundId'], '');
    final cancelled = await stays.watchMyHomestayBookings(guest.uid)
        .firstWhere((l) => l.any((s) => s.id == payId && s.status == 'cancelled'));
    expect(cancelled.firstWhere((s) => s.id == payId).refundAmount, 0);

    // Idempotent: a second call finds a non-paid booking.
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': payId}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'failed-precondition')));

    await auth.signOut();
  });
}
