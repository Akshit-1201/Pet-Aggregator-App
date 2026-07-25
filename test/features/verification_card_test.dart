// KYC submission. The security-relevant property is that the applicant writes
// only their own side — a client that could set `status` or `reviewedBy` could
// verify itself, and the badge would mean nothing again.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/data/models/verification_request.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/verification/verification_card.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required InMemoryVerificationRepository verification,
  required VerificationKind kind,
}) async {
  final overrides = <Override>[
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    verificationRepositoryProvider.overrideWithValue(verification),
    imagePickerServiceProvider
        .overrideWithValue(FakeImagePickerService(kTinyPng)),
  ];
  await pumpPg(
    tester,
    ProviderScope(overrides: overrides, child: VerificationCard(kind: kind)),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the applicant payload carries no review fields', () {
    const req = VerificationRequest(
      uid: 'u1', kind: VerificationKind.pro, applicantName: 'Aarav',
      area: 'Bandra West', docPaths: ['verification/u1/doc_0.jpg'],
      submittedAt: 100);
    final m = req.toMap();
    // firestore.rules rejects a client write touching any of these; toMap must
    // not emit them, or every legitimate submission would be denied.
    expect(m.containsKey('reviewedAt'), isFalse);
    expect(m.containsKey('reviewedBy'), isFalse);
    expect(m.containsKey('reason'), isFalse);
    expect(m['status'], 'pending');
  });

  test('docPaths are Storage object paths, never download URLs', () async {
    // A download URL for an ID document is a public link to someone's passport.
    final repo = InMemoryVerificationRepository();
    final path = await repo.uploadDocument(uid: 'u1', bytes: Uint8List(4), index: 0);
    expect(path, 'verification/u1/doc_0.jpg');
    expect(path.startsWith('http'), isFalse);
  });

  testWidgets('submitting uploads the docs and files a pending request',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'pro@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final verification = InMemoryVerificationRepository();

    await _pumpCard(tester,
        auth: auth, verification: verification, kind: VerificationKind.pro);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit for review'));
    await tester.pumpAndSettle();

    expect(verification.uploaded, ['verification/$uid/doc_0.jpg']);
    final filed = verification.requests[uid]!;
    expect(filed.status, VerificationStatus.pending);
    expect(filed.kind, VerificationKind.pro);
    expect(find.text('Under review. We usually reply within 2 days.'), findsOneWidget);
  });

  testWidgets('a rejection shows the reason and lets them re-apply', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'pro@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final verification = InMemoryVerificationRepository();
    await verification.submit(VerificationRequest(
      uid: uid, kind: VerificationKind.pro, applicantName: 'Aarav',
      area: 'Bandra West', docPaths: ['verification/$uid/doc_0.jpg'],
      submittedAt: 100));
    verification.review(uid, VerificationStatus.rejected,
        reason: 'The ID photo was too blurry to read.');

    await _pumpCard(tester,
        auth: auth, verification: verification, kind: VerificationKind.pro);

    expect(find.text('The ID photo was too blurry to read.'), findsOneWidget);
    expect(find.text('You can send new documents.'), findsOneWidget);
  });

  testWidgets('an approved partner sees confirmation, not the form', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final verification = InMemoryVerificationRepository();
    await verification.submit(VerificationRequest(
      uid: uid, kind: VerificationKind.homestay, applicantName: 'Meera',
      area: 'Bandra West', docPaths: ['verification/$uid/doc_0.jpg'],
      submittedAt: 100));
    verification.review(uid, VerificationStatus.approved);

    await _pumpCard(tester,
        auth: auth, verification: verification, kind: VerificationKind.homestay);

    expect(find.text("You're verified. The badge shows on your listing."),
        findsOneWidget);
    expect(find.text('Submit for review'), findsNothing);
  });
}
