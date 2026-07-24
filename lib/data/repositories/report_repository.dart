import '../models/report.dart';

/// Reports are write-only from the app: a client can file one but can never read
/// the queue back (see `firestore.rules`), so one user cannot enumerate what
/// others have reported. `plan.md` Phase 12 already reserves a `reports`
/// collection for the admin panel — this writes the same shape, so the moderation
/// queue has real data waiting when that gets built.
abstract interface class ReportRepository {
  Future<void> submitReport(Report report);
}
