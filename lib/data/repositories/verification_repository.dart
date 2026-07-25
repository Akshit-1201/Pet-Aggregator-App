import 'dart:typed_data';
import '../models/verification_request.dart';

abstract interface class VerificationRepository {
  /// The signed-in user's own request, or null if they've never applied.
  Stream<VerificationRequest?> watchMyRequest(String uid);

  /// Uploads one KYC image and returns its Storage **object path**.
  ///
  /// Returns a path rather than a download URL on purpose — see the note on
  /// [VerificationRequest.docPaths]. A download URL for an ID document would be
  /// a public link to someone's passport.
  Future<String> uploadDocument({required String uid, required Uint8List bytes, required int index});

  Future<void> submit(VerificationRequest request);
}
