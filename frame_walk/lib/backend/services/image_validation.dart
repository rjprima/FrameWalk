import 'dart:typed_data';

// Checks that picked files really are photos, by their bytes rather than their
// file name or the type the picker reports.
//
// No resizing or re-encoding happens here, so photos keep their full quality.
// To make uploads faster, the frontend can ask the picker for a smaller image
// (image_picker's maxWidth / imageQuality).
class ImageValidation {
  // Large enough for full-resolution photos from phones and from most
  // dedicated cameras, as JPEG or HEIC. Bigger files make the 3-second save
  // target unrealistic on mobile data. storage.rules and firestore.rules
  // enforce the same limit.
  static const int maxBytes = 20 * 1024 * 1024;

  static const Set<String> allowedContentTypes = {
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
  };

  // HEIF brands written by iPhones and cameras. 'mif1'/'msf1' are the generic
  // HEIF brands. AVIF ('avif') is not accepted.
  static const Set<String> _heicBrands = {'heic', 'heix', 'hevc', 'hevx'};
  static const Set<String> _heifBrands = {'mif1', 'msf1', 'heim', 'heis'};

  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ];

  // The image type of [bytes], or null if they aren't a supported image.
  static String? detectContentType(Uint8List bytes) {
    if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (_startsWith(bytes, _pngSignature)) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 12) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 12 && _ascii(bytes, 4, 8) == 'ftyp') {
      final brand = _ascii(bytes, 8, 12);
      if (_heicBrands.contains(brand)) return 'image/heic';
      if (_heifBrands.contains(brand)) return 'image/heif';
    }
    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _ascii(Uint8List bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));
}
