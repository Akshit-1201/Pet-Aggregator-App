// integration_test/functions_test.dart
//
// Verifies the payment callables against the Functions emulator. Run with:
//   npm --prefix functions run build
//   firebase emulators:start --only auth,functions --project pet-aggregator-app
//   flutter test integration_test/functions_test.dart -d emulator-5554
// Requires functions/.secret.local containing RAZORPAY_KEY_SECRET=test_secret
// (git-ignored; recreate on a fresh clone).
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pet_aggregator_app/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
    FirebaseFunctions.instanceFor(region: 'asia-south1')
        .useFunctionsEmulator('10.0.2.2', 5001);
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
}
