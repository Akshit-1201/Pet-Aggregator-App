import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

abstract interface class ImagePickerService {
  /// Opens the gallery picker; returns downsized JPEG bytes, or null if cancelled.
  Future<Uint8List?> pickImage();
}

class ImagePickerServiceImpl implements ImagePickerService {
  final ImagePicker _picker;
  ImagePickerServiceImpl([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  @override
  Future<Uint8List?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
    if (file == null) return null;
    return file.readAsBytes();
  }
}
