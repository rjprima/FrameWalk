import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

// Thrown by a PhotoStorage. [notFound] is true when the object doesn't exist,
// which deletions treat as already done.
class PhotoStorageException implements Exception {
  final String code;
  final String message;

  const PhotoStorageException(this.code, this.message);

  bool get notFound => code == 'object-not-found';

  @override
  String toString() => 'PhotoStorageException($code): $message';
}

// Stores and retrieves image files. Firebase Storage in the app; a fake in
// tests (test/fakes/fake_photo_storage.dart).
abstract class PhotoStorage {
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    Map<String, String> customMetadata = const {},
    void Function(int bytesSent, int totalBytes)? onProgress,
  });

  // Throws a PhotoStorageException with notFound set if [path] doesn't exist.
  Future<void> delete(String path);

  // Reads the file through the signed-in user's credentials, so security
  // rules are checked on every read.
  Future<Uint8List> download(String path, {required int maxSizeBytes});

  // A long-lived URL for Image.network. Anyone holding it can read the file
  // until its token is revoked in the Firebase console, so don't share or log
  // it.
  Future<String> downloadUrl(String path);
}

class FirebasePhotoStorage implements PhotoStorage {
  final FirebaseStorage _storage;

  FirebasePhotoStorage({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    Map<String, String> customMetadata = const {},
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    final task = _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: customMetadata,
          ),
        );
    StreamSubscription<TaskSnapshot>? progress;
    if (onProgress != null) {
      progress = task.snapshotEvents.listen(
        (snapshot) =>
            onProgress(snapshot.bytesTransferred, snapshot.totalBytes),
        onError: (Object _) {}, // Reported by awaiting the task below.
      );
    }
    try {
      await _guard(() => task);
    } finally {
      await progress?.cancel();
    }
  }

  @override
  Future<void> delete(String path) => _guard(() => _storage.ref(path).delete());

  @override
  Future<Uint8List> download(String path, {required int maxSizeBytes}) async {
    final data = await _guard(() => _storage.ref(path).getData(maxSizeBytes));
    if (data == null) {
      throw const PhotoStorageException('object-not-found', 'No data');
    }
    return data;
  }

  @override
  Future<String> downloadUrl(String path) =>
      _guard(() => _storage.ref(path).getDownloadURL());

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (error) {
      throw PhotoStorageException(error.code, error.message ?? error.code);
    }
  }
}
