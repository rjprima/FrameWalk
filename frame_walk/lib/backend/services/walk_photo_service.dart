import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/walk_photo.dart';
import '../../models/walked_route.dart';
import 'image_validation.dart';
import 'photo_storage.dart';
import 'walk_repository.dart';

// Photos for completed walks: listing them, uploading, changing which prompt
// they belong to, and deleting them. The image files go in Firebase Storage
// and their metadata in Firestore:
//
//   users/{uid}/walks/{walkedRouteId}/photos/{photoId}       WalkPhoto
//   users/{uid}/walkedRoutes/{walkedRouteId}/photos/{photoId} image file
//
// Every call works on the signed-in user's own data. There is no way to name
// another user, and firestore.rules / storage.rules enforce the same thing on
// the server.
//
// Editing flow: the frontend stages edits in a PhotoChangeSet (no network
// use) and passes it to saveChanges when the user taps Save. Uploads,
// metadata writes, and deletions then run in that order. See saveChanges.
//
// Photos are tied to prompts only by the stopId the user chooses, never by
// photo time, GPS, EXIF data, or prompt text. Deleting a photo here never
// touches the original on the user's device.
class WalkPhotoService {
  // Uploads at once. More rarely helps on a phone connection and uses more
  // memory.
  static const int maxConcurrentUploads = 3;

  // Firestore batches are capped at 500 writes.
  static const int maxChangesPerSave = 400;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final PhotoStorage _storage;
  final WalkRepository _walks;
  final DateTime Function() _clock;

  WalkPhotoService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    PhotoStorage? storage,
    WalkRepository? walkRepository,
    DateTime Function()? clock,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebasePhotoStorage(),
       _walks =
           walkRepository ??
           WalkRepository(firestore: firestore ?? FirebaseFirestore.instance),
       _clock = clock ?? DateTime.now;

  static String storagePathFor(
    String userId,
    String walkedRouteId,
    String photoId,
  ) => 'users/$userId/walkedRoutes/$walkedRouteId/photos/$photoId';

  // ---------------------------------------------------------------- reading

  // The walk's photos, oldest upload first. Empty if it has none. Only
  // metadata is read; load images one at a time with loadPhotoBytes or
  // photoDownloadUrl as they scroll into view.
  Future<List<WalkPhoto>> fetchPhotos(String walkedRouteId) async {
    final uid = _requireUid();
    await _loadWalk(uid, walkedRouteId);
    return _queryPhotos(uid, walkedRouteId);
  }

  // The prompts this particular walk showed, in route order, from its
  // WalkedStops (not the predefined route, which may have changed since).
  Future<List<WalkPrompt>> fetchPrompts(String walkedRouteId) async {
    final walk = await _loadWalk(_requireUid(), walkedRouteId);
    return _promptsOf(walk);
  }

  // The walk, its prompts, and its photos together, for the Activity page.
  Future<WalkPhotoGallery> fetchGallery(String walkedRouteId) async {
    final uid = _requireUid();
    final walk = await _loadWalk(uid, walkedRouteId);
    final photos = await _queryPhotos(uid, walkedRouteId);
    return WalkPhotoGallery(
      walk: walk,
      prompts: _promptsOf(walk),
      photos: photos,
    );
  }

  // The image itself, read through the user's credentials so security rules
  // are checked. Use Image.memory(bytes, cacheWidth: ...) for thumbnails.
  Future<Uint8List> loadPhotoBytes(WalkPhoto photo) async {
    final path = _verifiedPath(photo);
    try {
      return await _storage.download(
        path,
        maxSizeBytes: ImageValidation.maxBytes,
      );
    } on PhotoStorageException catch (error) {
      throw PhotoFailure(
        error.notFound
            ? PhotoErrorCode.photoNotFound
            : PhotoErrorCode.downloadFailed,
        'Could not load the photo',
        photoId: photo.photoId,
        cause: error,
      );
    }
  }

  // A URL for Image.network. Only an owner can get one, but anyone holding
  // the URL can read the image, so don't log or share it.
  Future<String> photoDownloadUrl(WalkPhoto photo) async {
    final path = _verifiedPath(photo);
    try {
      return await _storage.downloadUrl(path);
    } on PhotoStorageException catch (error) {
      throw PhotoFailure(
        error.notFound
            ? PhotoErrorCode.photoNotFound
            : PhotoErrorCode.downloadFailed,
        'Could not load the photo',
        photoId: photo.photoId,
        cause: error,
      );
    }
  }

  // ---------------------------------------------------------------- staging

  // Checks a picked image and gives it a photo ID. Call this when the user
  // picks a photo, so invalid files are rejected right away. Nothing is
  // uploaded until saveChanges. Throws PhotoFailure (invalidImage or
  // imageTooLarge).
  PendingPhoto preparePhoto(
    Uint8List bytes, {
    String? stopId,
    String? fileName,
  }) {
    if (bytes.isEmpty) {
      throw const PhotoFailure(
        PhotoErrorCode.invalidImage,
        'The file is empty',
      );
    }
    if (bytes.lengthInBytes > ImageValidation.maxBytes) {
      throw const PhotoFailure(
        PhotoErrorCode.imageTooLarge,
        'Photos must be 20 MB or smaller',
      );
    }
    final contentType = ImageValidation.detectContentType(bytes);
    if (contentType == null) {
      throw const PhotoFailure(
        PhotoErrorCode.invalidImage,
        'Only JPEG, PNG, HEIC, HEIF, and WebP photos can be added',
      );
    }
    return PendingPhoto(
      photoId: _firestore.collection('users').doc().id,
      bytes: bytes,
      contentType: contentType,
      stopId: stopId,
      fileName: fileName,
    );
  }

  // ----------------------------------------------------------------- saving

  // Saves staged edits for one walk, in this order:
  //
  //   1. Check the request: signed in, the walk is the user's and completed,
  //      every stopId is one of this walk's stops, and every edited photo
  //      exists. Any problem throws PhotoFailure before anything changes.
  //   2. Upload new images (up to [maxConcurrentUploads] at once).
  //   3. In one Firestore batch, write metadata for the uploaded photos and
  //      the association changes. If this fails, the files just uploaded
  //      are deleted again so none are left without metadata.
  //   4. Only if every upload and write succeeded: delete removed photos,
  //      metadata first, then files.
  //
  // Storage and Firestore can't share a transaction, so a save can partly
  // succeed. It never throws for a failed upload or write. Instead,
  // [PhotoSaveResult.remaining] holds exactly the changes still to save; pass
  // it to saveChanges again to retry. Retrying an already-saved photo is
  // harmless.
  Future<PhotoSaveResult> saveChanges(
    String walkedRouteId,
    PhotoChangeSet changes, {
    void Function(SaveProgress progress)? onProgress,
  }) async {
    final total = Stopwatch()..start();
    final uid = _requireUid();
    final walk = await _loadWalk(uid, walkedRouteId);
    if (!walk.isCompleted) {
      throw const PhotoFailure(
        PhotoErrorCode.walkNotCompleted,
        'Photos can only be added to a finished walk',
      );
    }
    if (changes.changeCount > maxChangesPerSave) {
      throw const PhotoFailure(
        PhotoErrorCode.tooManyChanges,
        'Too many changes to save at once',
      );
    }

    // 1. Validate.
    final existing = {
      for (final photo in await _queryPhotos(uid, walkedRouteId))
        photo.photoId: photo,
    };
    final validStops = walk.stopIds.toSet();
    void checkStop(String? stopId, String photoId) {
      if (stopId != null && !validStops.contains(stopId)) {
        throw PhotoFailure(
          PhotoErrorCode.invalidStop,
          'That prompt is not part of this walk',
          photoId: photoId,
        );
      }
    }

    final uploads = <PendingPhoto>[];
    final stopChanges = <String, String?>{};
    for (final photo in changes.additions) {
      _checkId(photo.photoId);
      checkStop(photo.stopId, photo.photoId);
      _checkPendingImage(photo);
      final saved = existing[photo.photoId];
      if (saved == null) {
        uploads.add(photo);
      } else if (saved.stopId != photo.stopId) {
        // Already saved by an earlier attempt; just make its prompt match.
        stopChanges[photo.photoId] = photo.stopId;
      }
    }
    changes.stopChanges.forEach((photoId, stopId) {
      _checkId(photoId);
      checkStop(stopId, photoId);
      final saved = existing[photoId];
      if (saved == null) {
        throw PhotoFailure(
          PhotoErrorCode.photoNotFound,
          'That photo no longer exists',
          photoId: photoId,
        );
      }
      if (saved.stopId != stopId) stopChanges[photoId] = stopId;
    });
    for (final photoId in changes.deletions) {
      _checkId(photoId);
      stopChanges.remove(photoId);
    }
    final validated = total.elapsed;

    // 2. Upload.
    final uploadWatch = Stopwatch()..start();
    final outcomes = await _uploadAll(uid, walkedRouteId, uploads, onProgress);
    uploadWatch.stop();
    final uploaded = <PendingPhoto>[];
    final failedUploads = <PendingPhoto>[];
    final errors = <PhotoSaveError>[];
    for (var i = 0; i < uploads.length; i++) {
      final error = outcomes[i];
      if (error == null) {
        uploaded.add(uploads[i]);
      } else {
        failedUploads.add(uploads[i]);
        errors.add(
          PhotoSaveError(
            PhotoErrorCode.uploadFailed,
            'Upload failed: ${error.message}',
            photoId: uploads[i].photoId,
          ),
        );
      }
    }

    // 3. Metadata and association changes, all or nothing.
    final now = _clock();
    final newPhotos = [
      for (final photo in uploaded)
        WalkPhoto(
          photoId: photo.photoId,
          userId: uid,
          walkedRouteId: walkedRouteId,
          storagePath: storagePathFor(uid, walkedRouteId, photo.photoId),
          stopId: photo.stopId,
          uploadedAt: now,
          contentType: photo.contentType,
          sizeBytes: photo.sizeBytes,
        ),
    ];
    final databaseWatch = Stopwatch()..start();
    final orphans = <String>[];
    if (newPhotos.isNotEmpty || stopChanges.isNotEmpty) {
      final batch = _firestore.batch();
      for (final photo in newPhotos) {
        batch.set(
          _photos(uid, walkedRouteId).doc(photo.photoId),
          photo.toMap(),
        );
      }
      stopChanges.forEach((photoId, stopId) {
        batch.update(_photos(uid, walkedRouteId).doc(photoId), {
          'stopId': stopId,
          'updatedAt': Timestamp.fromDate(now),
        });
      });
      try {
        await batch.commit();
      } catch (error) {
        databaseWatch.stop();
        // Nothing was written, so remove the files that would have no
        // metadata. The whole change set is left to retry.
        for (final photo in uploaded) {
          final path = storagePathFor(uid, walkedRouteId, photo.photoId);
          if (!await _deleteFile(path)) orphans.add(path);
        }
        errors.add(
          PhotoSaveError(
            PhotoErrorCode.databaseFailed,
            'Could not save photo details: $error',
          ),
        );
        return PhotoSaveResult(
          photos: existing.values.toList(),
          added: const [],
          updatedPhotoIds: const [],
          deletedPhotoIds: const [],
          remaining: changes.copy(),
          errors: errors,
          orphanedStoragePaths: orphans,
          timings: SaveTimings(
            validation: validated,
            upload: uploadWatch.elapsed,
            database: databaseWatch.elapsed,
            deletion: Duration.zero,
            total: total.elapsed,
          ),
        );
      }
    }
    databaseWatch.stop();

    final current = Map<String, WalkPhoto>.of(existing);
    for (final photo in newPhotos) {
      current[photo.photoId] = photo;
    }
    stopChanges.forEach((photoId, stopId) {
      current[photoId] = current[photoId]!.withStop(stopId, now);
    });

    // 4. Deletions, only once everything new is safely saved.
    final remaining = PhotoChangeSet();
    failedUploads.forEach(remaining.add);
    final deleted = <String>[];
    final deletionWatch = Stopwatch()..start();
    if (failedUploads.isNotEmpty) {
      changes.deletions.forEach(remaining.remove);
    } else if (changes.deletions.isNotEmpty) {
      final batch = _firestore.batch();
      for (final photoId in changes.deletions) {
        if (existing.containsKey(photoId)) {
          batch.delete(_photos(uid, walkedRouteId).doc(photoId));
        }
      }
      try {
        await batch.commit();
        for (final photoId in changes.deletions) {
          deleted.add(photoId);
          current.remove(photoId);
        }
        // The photo is gone for the user once its metadata is. A file left
        // behind is only wasted space, so it's reported, not retried.
        final results = await Future.wait([
          for (final photoId in changes.deletions)
            _deleteFile(storagePathFor(uid, walkedRouteId, photoId)),
        ]);
        for (var i = 0; i < results.length; i++) {
          if (!results[i]) {
            orphans.add(
              storagePathFor(
                uid,
                walkedRouteId,
                changes.deletions.elementAt(i),
              ),
            );
          }
        }
      } catch (error) {
        changes.deletions.forEach(remaining.remove);
        errors.add(
          PhotoSaveError(
            PhotoErrorCode.databaseFailed,
            'Could not delete photos: $error',
          ),
        );
      }
    }
    deletionWatch.stop();
    total.stop();

    final photos = current.values.toList()..sort(_byUpload);
    return PhotoSaveResult(
      photos: photos,
      added: newPhotos,
      updatedPhotoIds: stopChanges.keys.toList(),
      deletedPhotoIds: deleted,
      remaining: remaining,
      errors: errors,
      orphanedStoragePaths: orphans,
      timings: SaveTimings(
        validation: validated,
        upload: uploadWatch.elapsed,
        database: databaseWatch.elapsed,
        deletion: deletionWatch.elapsed,
        total: total.elapsed,
      ),
    );
  }

  // ------------------------------------------------- single-change shortcuts
  //
  // Each is saveChanges with one kind of change. They throw PhotoFailure if
  // anything didn't save.

  // Returns the saved photos in the same order as [photos].
  Future<List<WalkPhoto>> uploadPhotos(
    String walkedRouteId,
    List<PendingPhoto> photos, {
    void Function(SaveProgress progress)? onProgress,
  }) async {
    final changes = PhotoChangeSet();
    photos.forEach(changes.add);
    final result = await saveChanges(
      walkedRouteId,
      changes,
      onProgress: onProgress,
    );
    result.throwIfIncomplete();
    // In the order given, so callers can match results to their inputs.
    final saved = {for (final photo in result.photos) photo.photoId: photo};
    return [for (final photo in photos) saved[photo.photoId]!];
  }

  // Changes the prompt a saved photo belongs to, without re-uploading it.
  // [stopId] null means "No prompt".
  Future<WalkPhoto> updatePhotoStop(
    String walkedRouteId,
    String photoId,
    String? stopId,
  ) async {
    final result = await saveChanges(
      walkedRouteId,
      PhotoChangeSet()..setStop(photoId, stopId),
    );
    result.throwIfIncomplete();
    return result.photos.firstWhere((photo) => photo.photoId == photoId);
  }

  // Removes a photo from FrameWalk. Deleting one that is already gone
  // succeeds.
  Future<void> deletePhoto(String walkedRouteId, String photoId) async {
    final result = await saveChanges(
      walkedRouteId,
      PhotoChangeSet()..remove(photoId),
    );
    result.throwIfIncomplete();
  }

  // ---------------------------------------------------------------- helpers

  CollectionReference<Map<String, dynamic>> _photos(
    String uid,
    String walkedRouteId,
  ) => _firestore
      .collection('users')
      .doc(uid)
      .collection('walks')
      .doc(walkedRouteId)
      .collection('photos');

  String _requireUid() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const PhotoFailure(PhotoErrorCode.notSignedIn, 'Please log in');
    }
    return user.uid;
  }

  // Only finds walks under the signed-in user, so another user's walk ID
  // looks the same as a missing one.
  Future<WalkedRoute> _loadWalk(String uid, String walkedRouteId) async {
    if (!_isValidId(walkedRouteId)) {
      throw const PhotoFailure(PhotoErrorCode.walkNotFound, 'Walk not found');
    }
    final WalkedRoute? walk;
    try {
      walk = await _walks.fetchWalk(uid, walkedRouteId);
    } on FirebaseException catch (error) {
      throw _readFailure(error);
    }
    if (walk == null || walk.userId != uid) {
      throw const PhotoFailure(PhotoErrorCode.walkNotFound, 'Walk not found');
    }
    return walk;
  }

  Future<List<WalkPhoto>> _queryPhotos(String uid, String walkedRouteId) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _photos(uid, walkedRouteId).get();
    } on FirebaseException catch (error) {
      throw _readFailure(error);
    }
    final photos = <WalkPhoto>[];
    for (final doc in snapshot.docs) {
      final photo = WalkPhoto.fromMap(doc.id, doc.data());
      // Skip anything that doesn't belong exactly here; the rules shouldn't
      // allow it, but this keeps walks from ever showing each other's photos.
      if (photo.userId == uid &&
          photo.walkedRouteId == walkedRouteId &&
          photo.storagePath == storagePathFor(uid, walkedRouteId, doc.id)) {
        photos.add(photo);
      }
    }
    return photos..sort(_byUpload);
  }

  // Permission errors are reported as not found, so they reveal nothing about
  // other users' data.
  PhotoFailure _readFailure(FirebaseException error) =>
      error.code == 'permission-denied'
      ? PhotoFailure(
          PhotoErrorCode.walkNotFound,
          'Walk not found',
          cause: error,
        )
      : PhotoFailure(
          PhotoErrorCode.databaseFailed,
          'Could not load photos. Check your connection.',
          cause: error,
        );

  List<WalkPrompt> _promptsOf(WalkedRoute walk) =>
      walk.stops.map(WalkPrompt.fromStop).toList();

  // Never trusts a stored path; recomputes it from the photo's IDs.
  String _verifiedPath(WalkPhoto photo) {
    final uid = _requireUid();
    final path = storagePathFor(uid, photo.walkedRouteId, photo.photoId);
    if (photo.userId != uid || photo.storagePath != path) {
      throw PhotoFailure(
        PhotoErrorCode.photoNotFound,
        'Photo not found',
        photoId: photo.photoId,
      );
    }
    return path;
  }

  void _checkPendingImage(PendingPhoto photo) {
    if (photo.sizeBytes == 0 ||
        photo.sizeBytes > ImageValidation.maxBytes ||
        ImageValidation.detectContentType(photo.bytes) != photo.contentType) {
      throw PhotoFailure(
        PhotoErrorCode.invalidImage,
        'Photo was not prepared with preparePhoto',
        photoId: photo.photoId,
      );
    }
  }

  void _checkId(String id) {
    if (!_isValidId(id)) {
      throw PhotoFailure(
        PhotoErrorCode.photoNotFound,
        'Invalid photo ID',
        photoId: id,
      );
    }
  }

  static bool _isValidId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);

  // Uploads in parallel, a few at a time. Returns null for each success, or
  // the error.
  Future<List<PhotoStorageException?>> _uploadAll(
    String uid,
    String walkedRouteId,
    List<PendingPhoto> photos,
    void Function(SaveProgress progress)? onProgress,
  ) async {
    final results = List<PhotoStorageException?>.filled(photos.length, null);
    final sent = List<int>.filled(photos.length, 0);
    final totalBytes = photos.fold<int>(0, (total, p) => total + p.sizeBytes);
    var finished = 0;
    void report() => onProgress?.call(
      SaveProgress(
        photosUploaded: finished,
        photosTotal: photos.length,
        bytesSent: sent.fold(0, (a, b) => a + b),
        bytesTotal: totalBytes,
      ),
    );

    var next = 0;
    Future<void> worker() async {
      while (next < photos.length) {
        final i = next++;
        final photo = photos[i];
        try {
          await _storage.upload(
            storagePathFor(uid, walkedRouteId, photo.photoId),
            photo.bytes,
            contentType: photo.contentType,
            customMetadata: {
              'walkedRouteId': walkedRouteId,
              'photoId': photo.photoId,
            },
            onProgress: (bytesSent, _) {
              sent[i] = bytesSent;
              report();
            },
          );
          sent[i] = photo.sizeBytes;
        } on PhotoStorageException catch (error) {
          results[i] = error;
        } catch (error) {
          results[i] = PhotoStorageException('unknown', '$error');
        }
        finished++;
        report();
      }
    }

    await Future.wait([
      for (var w = 0; w < min(maxConcurrentUploads, photos.length); w++)
        worker(),
    ]);
    return results;
  }

  // True if the file is gone afterwards, including if it was already missing.
  Future<bool> _deleteFile(String path) async {
    try {
      await _storage.delete(path);
      return true;
    } on PhotoStorageException catch (error) {
      return error.notFound;
    } catch (_) {
      return false;
    }
  }

  static int _byUpload(WalkPhoto a, WalkPhoto b) {
    final byTime = a.uploadedAt.compareTo(b.uploadedAt);
    return byTime != 0 ? byTime : a.photoId.compareTo(b.photoId);
  }
}

// ---------------------------------------------------------------- types

enum PhotoErrorCode {
  notSignedIn,
  walkNotFound,
  walkNotCompleted,
  invalidStop,
  photoNotFound,
  invalidImage,
  imageTooLarge,
  tooManyChanges,
  uploadFailed,
  databaseFailed,
  downloadFailed,
}

// A photo operation that failed. [message] is safe to show to the user.
class PhotoFailure implements Exception {
  final PhotoErrorCode code;
  final String message;
  final String? photoId;
  final Object? cause;

  const PhotoFailure(this.code, this.message, {this.photoId, this.cause});

  @override
  String toString() => 'PhotoFailure(${code.name}): $message';
}

// Photo edits staged in the editor until the user taps Save. Nothing here
// touches the network.
class PhotoChangeSet {
  final List<PendingPhoto> _additions = [];
  final Map<String, String?> _stopChanges = {};
  final Set<String> _deletions = {};

  List<PendingPhoto> get additions => List.unmodifiable(_additions);

  // Saved photo ID -> new stopId (null for "No prompt").
  Map<String, String?> get stopChanges => Map.unmodifiable(_stopChanges);

  Set<String> get deletions => Set.unmodifiable(_deletions);

  bool get isEmpty =>
      _additions.isEmpty && _stopChanges.isEmpty && _deletions.isEmpty;

  int get changeCount =>
      _additions.length + _stopChanges.length + _deletions.length;

  void add(PendingPhoto photo) {
    _additions.removeWhere((p) => p.photoId == photo.photoId);
    _additions.add(photo);
  }

  // Works for both new and saved photos. Ignored for a photo staged for
  // deletion.
  void setStop(String photoId, String? stopId) {
    final index = _additions.indexWhere((p) => p.photoId == photoId);
    if (index >= 0) {
      _additions[index] = _additions[index].withStop(stopId);
    } else if (!_deletions.contains(photoId)) {
      _stopChanges[photoId] = stopId;
    }
  }

  // A new photo is simply dropped; a saved one is staged for deletion.
  void remove(String photoId) {
    final before = _additions.length;
    _additions.removeWhere((p) => p.photoId == photoId);
    if (_additions.length == before) {
      _stopChanges.remove(photoId);
      _deletions.add(photoId);
    }
  }

  void clear() {
    _additions.clear();
    _stopChanges.clear();
    _deletions.clear();
  }

  PhotoChangeSet copy() {
    final copy = PhotoChangeSet();
    copy._additions.addAll(_additions);
    copy._stopChanges.addAll(_stopChanges);
    copy._deletions.addAll(_deletions);
    return copy;
  }
}

class SaveProgress {
  final int photosUploaded;
  final int photosTotal;
  final int bytesSent;
  final int bytesTotal;

  const SaveProgress({
    required this.photosUploaded,
    required this.photosTotal,
    required this.bytesSent,
    required this.bytesTotal,
  });

  double get fraction => bytesTotal == 0 ? 1 : bytesSent / bytesTotal;
}

class SaveTimings {
  final Duration validation;
  final Duration upload;
  final Duration database;
  final Duration deletion;
  final Duration total;

  const SaveTimings({
    required this.validation,
    required this.upload,
    required this.database,
    required this.deletion,
    required this.total,
  });

  @override
  String toString() =>
      'validation ${validation.inMilliseconds} ms, '
      'upload ${upload.inMilliseconds} ms, '
      'firestore ${database.inMilliseconds} ms, '
      'deletion ${deletion.inMilliseconds} ms, '
      'total ${total.inMilliseconds} ms';
}

class PhotoSaveError {
  final PhotoErrorCode code;
  final String message;
  final String? photoId;

  const PhotoSaveError(this.code, this.message, {this.photoId});

  @override
  String toString() =>
      'PhotoSaveError(${code.name}${photoId == null ? '' : ', $photoId'}): '
      '$message';
}

class PhotoSaveResult {
  // The walk's photos after this save, as best known; refresh the editor
  // from this.
  final List<WalkPhoto> photos;
  final List<WalkPhoto> added;
  final List<String> updatedPhotoIds;
  final List<String> deletedPhotoIds;

  // Changes that didn't save. Empty when the save fully succeeded. Keep
  // these staged and pass them to saveChanges to retry.
  final PhotoChangeSet remaining;
  final List<PhotoSaveError> errors;

  // Files that couldn't be removed from Storage. The user doesn't see them,
  // so they don't make the save fail.
  final List<String> orphanedStoragePaths;
  final SaveTimings timings;

  const PhotoSaveResult({
    required this.photos,
    required this.added,
    required this.updatedPhotoIds,
    required this.deletedPhotoIds,
    required this.remaining,
    required this.errors,
    required this.orphanedStoragePaths,
    required this.timings,
  });

  bool get isComplete => remaining.isEmpty;

  void throwIfIncomplete() {
    if (isComplete) return;
    final first = errors.isEmpty ? null : errors.first;
    throw PhotoFailure(
      first?.code ?? PhotoErrorCode.databaseFailed,
      first?.message ?? 'Some changes were not saved',
      photoId: first?.photoId,
    );
  }
}
