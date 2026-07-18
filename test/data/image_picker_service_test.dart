import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

void main() {
  test('FakeImagePickerService returns the configured bytes and counts calls', () async {
    final bytes = Uint8List.fromList([9, 9]);
    final picker = FakeImagePickerService(bytes);
    expect(await picker.pickImage(), bytes);
    expect(picker.calls, 1);
  });

  test('FakeImagePickerService returns null when nothing is configured (cancelled pick)', () async {
    final picker = FakeImagePickerService();
    expect(await picker.pickImage(), isNull);
    expect(picker.calls, 1);
  });
}
