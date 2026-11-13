import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/image_validation.dart';

void main() {
  Uint8List bytes(List<int> head) =>
      Uint8List.fromList([...head, ...List.filled(16, 0)]);

  Uint8List ftyp(String brand) =>
      bytes([0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...brand.codeUnits]);

  test('recognizes supported photo formats by their bytes', () {
    expect(
      ImageValidation.detectContentType(bytes([0xFF, 0xD8, 0xFF, 0xE1])),
      'image/jpeg',
    );
    expect(
      ImageValidation.detectContentType(
        bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      'image/png',
    );
    expect(
      ImageValidation.detectContentType(
        bytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]),
      ),
      'image/webp',
    );
    // iPhone photos.
    expect(ImageValidation.detectContentType(ftyp('heic')), 'image/heic');
    expect(ImageValidation.detectContentType(ftyp('mif1')), 'image/heif');
  });

  test('rejects other files', () {
    expect(ImageValidation.detectContentType(Uint8List(0)), isNull);
    expect(
      ImageValidation.detectContentType(bytes('GIF89a'.codeUnits)),
      isNull,
    );
    expect(ImageValidation.detectContentType(bytes('%PDF-'.codeUnits)), isNull);
    expect(ImageValidation.detectContentType(ftyp('isom')), isNull); // MP4
    expect(ImageValidation.detectContentType(ftyp('avif')), isNull);
  });
}
