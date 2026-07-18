import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryStorageRepository stores the bytes and returns a URL', () async {
    final repo = InMemoryStorageRepository();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final url = await repo.uploadImage(path: 'users/u1/avatar.jpg', bytes: bytes);
    expect(url, 'https://fake.storage/users/u1/avatar.jpg');
    expect(repo.uploads['users/u1/avatar.jpg'], bytes);
  });
}
