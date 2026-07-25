/// Blocking is stored as `users/{myUid}/blocked/{otherUid}` — a subcollection of
/// the blocker's own doc, so the existing owner-only rule on `users` already
/// makes a block list private. Nobody can see who has blocked them.
///
/// Filtering happens client-side (Firestore can't filter a query per viewer), so
/// a block hides content in the app rather than making it unreadable. The one
/// place that is genuinely enforced is chat: a rule rejects messages to someone
/// who has blocked you, because "they can still message me" is the failure that
/// actually matters.
abstract interface class BlockRepository {
  /// Uids [uid] has blocked.
  Stream<Set<String>> watchBlockedUids(String uid);

  /// The blocked list with names, for the Settings screen.
  ///
  /// [name] is stored at block time rather than looked up later: `users/{uid}`
  /// is owner-read-only, so the list could never resolve a name and showed
  /// "Pawgo user" for everyone.
  Stream<List<({String uid, String name})>> watchBlocked(String uid);

  Future<void> block(String uid, String blockedUid, {String name = ''});
  Future<void> unblock(String uid, String blockedUid);
}
