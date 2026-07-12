import '../models/homestay.dart';

abstract interface class HomestayRepository {
  Future<void> upsertHomestay(Homestay homestay);
  Stream<Homestay?> watchHomestay(String uid);
  Stream<List<Homestay>> watchHomestays();
}
