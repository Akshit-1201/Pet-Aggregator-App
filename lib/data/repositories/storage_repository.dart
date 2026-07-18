import 'dart:typed_data';

abstract interface class StorageRepository {
  /// Uploads [bytes] (a JPEG) to [path]; returns the public download URL.
  Future<String> uploadImage({required String path, required Uint8List bytes});
}
