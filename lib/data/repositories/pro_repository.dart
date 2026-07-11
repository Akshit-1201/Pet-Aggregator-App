import '../models/pro.dart';

abstract interface class ProRepository {
  Future<void> upsertPro(Pro pro);
  Stream<Pro?> watchPro(String uid);
  Stream<List<Pro>> watchPros();
}
