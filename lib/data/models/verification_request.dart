enum VerificationKind {
  pro('pro', 'service pro'),
  homestay('homestay', 'homestay host');

  final String storageKey, label;
  const VerificationKind(this.storageKey, this.label);

  static VerificationKind fromStorage(String key) => VerificationKind.values
      .firstWhere((k) => k.storageKey == key, orElse: () => VerificationKind.pro);
}

enum VerificationStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  final String storageKey;
  const VerificationStatus(this.storageKey);

  static VerificationStatus fromStorage(String key) => VerificationStatus.values
      .firstWhere((s) => s.storageKey == key, orElse: () => VerificationStatus.pending);
}

/// A partner's request to be Pawgo-verified, keyed by their uid — one active
/// request per person, matching how `pros/{uid}` and `homestays/{uid}` are keyed.
/// Re-applying after a rejection overwrites the old request.
class VerificationRequest {
  final String uid, applicantName, area, reviewedBy, reason;
  final VerificationKind kind;
  final VerificationStatus status;

  /// Storage **object paths**, deliberately not `getDownloadURL()` links.
  ///
  /// Every other image in Pawgo stores a download URL, which carries a token and
  /// is effectively a public link — fine for a pet photo, not for someone's ID.
  /// KYC objects are unreadable by clients (`storage.rules`), and the admin panel
  /// mints short-lived signed URLs server-side when a reviewer opens the request.
  final List<String> docPaths;

  final int submittedAt, reviewedAt;

  const VerificationRequest({
    required this.uid,
    required this.kind,
    required this.applicantName,
    required this.area,
    required this.docPaths,
    required this.submittedAt,
    this.status = VerificationStatus.pending,
    this.reviewedBy = '',
    this.reason = '',
    this.reviewedAt = 0,
  });

  /// What the applicant writes. Excludes every review-side field — the rules
  /// reject a client write that touches them, so a partner cannot self-approve.
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'kind': kind.storageKey,
        'status': status.storageKey,
        'docPaths': docPaths,
        'applicantName': applicantName,
        'area': area,
        'submittedAt': submittedAt,
      };

  factory VerificationRequest.fromMap(String uid, Map<String, dynamic> m) =>
      VerificationRequest(
        uid: uid,
        kind: VerificationKind.fromStorage((m['kind'] ?? 'pro') as String),
        status: VerificationStatus.fromStorage((m['status'] ?? 'pending') as String),
        docPaths: ((m['docPaths'] ?? const []) as List).whereType<String>().toList(),
        applicantName: (m['applicantName'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        submittedAt: (m['submittedAt'] ?? 0) as int,
        reviewedAt: (m['reviewedAt'] ?? 0) as int,
        reviewedBy: (m['reviewedBy'] ?? '') as String,
        reason: (m['reason'] ?? '') as String,
      );
}
