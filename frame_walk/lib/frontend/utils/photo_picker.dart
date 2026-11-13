import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

// A photo picked from the device. Only its bytes and file name are used; the
// original stays in the user's photo library unchanged.
class PickedPhoto {
  final Uint8List bytes;
  final String name;

  const PickedPhoto(this.bytes, this.name);
}

// Lets screens be tested (or given a different picker) without image_picker.
typedef PickPhotos = Future<List<PickedPhoto>> Function();

// Opens the system photo picker (PHPicker on iOS, the Android photo picker)
// for several photos. Returns an empty list if the user cancels.
//
// requestFullMetadata: false means iOS doesn't ask for full photo-library
// access; FrameWalk doesn't use EXIF or location data. Photos are returned at
// full size. Pass maxWidth / imageQuality here to make uploads faster.
Future<List<PickedPhoto>> pickPhotosFromLibrary() async {
  final files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
  return [
    for (final file in files) PickedPhoto(await file.readAsBytes(), file.name),
  ];
}
