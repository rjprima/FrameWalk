import 'dart:typed_data';

import 'package:frame_walk/backend/services/photo_storage.dart';

class StoredFile {
  final Uint8List bytes;
  final String contentType;
  final Map<String, String> customMetadata;

  const StoredFile(this.bytes, this.contentType, this.customMetadata);
}

// An in-memory PhotoStorage. Set the fail* sets to simulate errors for
// particular paths.
class FakePhotoStorage implements PhotoStorage {
  final Map<String, StoredFile> files = {};

  // Paths whose upload / delete fails with a network-style error.
  final Set<String> failUploads = {};
  final Set<String> failDeletes = {};

  // Makes every upload fail, for when the photo ID isn't known in advance.
  bool failAllUploads = false;

  final List<String> uploadCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    Map<String, String> customMetadata = const {},
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    uploadCalls.add(path);
    await Future<void>.delayed(Duration.zero);
    if (failAllUploads || failUploads.contains(path)) {
      throw const PhotoStorageException('retry-limit-exceeded', 'offline');
    }
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    files[path] = StoredFile(bytes, contentType, customMetadata);
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<void> delete(String path) async {
    deleteCalls.add(path);
    if (failDeletes.contains(path)) {
      throw const PhotoStorageException('unknown', 'offline');
    }
    if (files.remove(path) == null) {
      throw const PhotoStorageException('object-not-found', 'missing');
    }
  }

  @override
  Future<Uint8List> download(String path, {required int maxSizeBytes}) async {
    final file = files[path];
    if (file == null) {
      throw const PhotoStorageException('object-not-found', 'missing');
    }
    return file.bytes;
  }

  @override
  Future<String> downloadUrl(String path) async {
    if (!files.containsKey(path)) {
      throw const PhotoStorageException('object-not-found', 'missing');
    }
    return 'https://storage.test/$path?token=fake';
  }
}
