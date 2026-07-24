/// What a report points at. `contextId` disambiguates nested content — a comment
/// needs its post id, a message needs its chat id — so a moderator can find the
/// thing without a collection-group scan.
enum ReportTargetType {
  post('post', 'post'),
  comment('comment', 'comment'),
  message('message', 'message'),
  user('user', 'person'),
  pro('pro', 'listing'),
  homestay('homestay', 'listing'),
  pet('pet', 'pet profile');

  final String storageKey, noun;
  const ReportTargetType(this.storageKey, this.noun);

  static ReportTargetType fromStorage(String key) =>
      ReportTargetType.values.firstWhere((t) => t.storageKey == key, orElse: () => ReportTargetType.post);
}

enum ReportReason {
  spam('spam', 'Spam or scam'),
  harassment('harassment', 'Harassment or bullying'),
  hate('hate', 'Hate speech'),
  sexual('sexual', 'Sexual or explicit content'),
  animalWelfare('animalWelfare', 'Animal welfare concern'),
  impersonation('impersonation', 'Impersonation or fake listing'),
  other('other', 'Something else');

  final String storageKey, label;
  const ReportReason(this.storageKey, this.label);

  static ReportReason fromStorage(String key) =>
      ReportReason.values.firstWhere((r) => r.storageKey == key, orElse: () => ReportReason.other);
}

class Report {
  final String id, reporterId, targetId, contextId, note;
  /// Uid of whoever authored the reported thing, when known — lets a moderator
  /// act on the person, not just the one item.
  final String targetOwnerId;
  final ReportTargetType targetType;
  final ReportReason reason;
  final int createdAt;

  const Report({
    this.id = '',
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.targetOwnerId = '',
    this.contextId = '',
    this.note = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'reporterId': reporterId,
        'targetType': targetType.storageKey,
        'targetId': targetId,
        'targetOwnerId': targetOwnerId,
        'contextId': contextId,
        'reason': reason.storageKey,
        'note': note,
        'createdAt': createdAt,
        // Moderation queue state. Clients can only ever create with 'open';
        // the admin panel owns every transition after that.
        'status': 'open',
      };

  factory Report.fromMap(String id, Map<String, dynamic> m) => Report(
        id: id,
        reporterId: (m['reporterId'] ?? '') as String,
        targetType: ReportTargetType.fromStorage((m['targetType'] ?? 'post') as String),
        targetId: (m['targetId'] ?? '') as String,
        targetOwnerId: (m['targetOwnerId'] ?? '') as String,
        contextId: (m['contextId'] ?? '') as String,
        reason: ReportReason.fromStorage((m['reason'] ?? 'other') as String),
        note: (m['note'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}
