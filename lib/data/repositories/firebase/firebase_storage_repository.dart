import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import '../storage_repository.dart';

class FirebaseStorageRepository implements StorageRepository {
  final FirebaseStorage _storage;
  FirebaseStorageRepository([FirebaseStorage? storage])
      : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<String> uploadImage({required String path, required Uint8List bytes}) async {
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
