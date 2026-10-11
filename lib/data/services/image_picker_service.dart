import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

abstract interface class ImagePickerService {
  /// Opens the gallery picker; returns downsized JPEG bytes, or null if cancelled.
  ///
  /// [maxWidth] caps the upload. 1080 suits full-width galleries; avatars only
  /// ever draw at ~50-80px, so they pass [avatarMaxWidth] — about a quarter of
  /// the bytes, which is most of what made profile icons slow to appear.
  Future<Uint8List?> pickImage({double maxWidth = 1080});
}

/// Upload width for profile pictures: crisp at the largest avatar size (~100
/// logical px on a 3x screen ≈ 300px) with headroom.
const double avatarMaxWidth = 512;

class ImagePickerServiceImpl implements ImagePickerService {
  final ImagePicker _picker;
  ImagePickerServiceImpl([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  @override
  Future<Uint8List?> pickImage({double maxWidth = 1080}) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: 80);
    if (file == null) return null;
    return file.readAsBytes();
  }
}
