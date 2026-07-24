import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/report.dart';
import '../report_repository.dart';

class FirestoreReportRepository implements ReportRepository {
  final FirebaseFirestore _db;
  FirestoreReportRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  @override
  Future<void> submitReport(Report report) => _db.collection('reports').add(report.toMap());
}
