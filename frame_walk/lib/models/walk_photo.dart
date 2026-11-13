import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'location_point.dart';
import 'walked_route.dart';

// A photo the user added to one completed walk (a WalkedRoute, not the
// predefined route), so photos from separate walks of the same route never mix.
//
//   Firestore: users/{userId}/walks/{walkedRouteId}/photos/{photoId}
//   Storage:   users/{userId}/walkedRoutes/{walkedRouteId}/photos/{photoId}
//
// The image file lives in Firebase Storage. This record holds only metadata
// and the prompt association. [stopId] is the WalkedStop.stopId whose prompt
// the photo answers, or null when the user chose "No prompt". Several photos
// can share a stop.
class WalkPhoto {
  final String photoId;
  final String userId;
  final String walkedRouteId;
  final String storagePath;
  final String? stopId;
  final DateTime uploadedAt;
  final DateTime? updatedAt;
  final String contentType;
  final int sizeBytes;

  const WalkPhoto({
    required this.photoId,
    required this.userId,
    required this.walkedRouteId,
    required this.storagePath,
    required this.uploadedAt,
    required this.contentType,
    required this.sizeBytes,
    this.stopId,
    this.updatedAt,
  });

  WalkPhoto withStop(String? newStopId, DateTime time) => WalkPhoto(
    photoId: photoId,
    userId: userId,
    walkedRouteId: walkedRouteId,
    storagePath: storagePath,
    stopId: newStopId,
    uploadedAt: uploadedAt,
    updatedAt: time,
    contentType: contentType,
    sizeBytes: sizeBytes,
  );

  Map<String, dynamic> toMap() => {
    'photoId': photoId,
    'userId': userId,
    'walkedRouteId': walkedRouteId,
    'storagePath': storagePath,
    'stopId': stopId,
    'uploadedAt': Timestamp.fromDate(uploadedAt),
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    'contentType': contentType,
    'sizeBytes': sizeBytes,
  };

  factory WalkPhoto.fromMap(String id, Map<String, dynamic> map) => WalkPhoto(
    photoId: id,
    userId: map['userId'] as String,
    walkedRouteId: map['walkedRouteId'] as String,
    storagePath: map['storagePath'] as String,
    stopId: map['stopId'] as String?,
    uploadedAt: readTimestamp(map['uploadedAt'])!,
    updatedAt: readTimestamp(map['updatedAt']),
    contentType: map['contentType'] as String,
    sizeBytes: (map['sizeBytes'] as num).toInt(),
  );
}

// A prompt that was presented on one particular walk, taken from its
// WalkedStop. Offered as an association option. The frontend adds its own
// "No prompt" option, which maps to a null stopId.
class WalkPrompt {
  final String stopId;
  final String stopName;
  final String prompt;

  // When the user reached the stop, or null if GPS never registered it. Still
  // offered, because a missed GPS fix doesn't mean the user wasn't there.
  final DateTime? reachedAt;

  const WalkPrompt({
    required this.stopId,
    required this.stopName,
    required this.prompt,
    this.reachedAt,
  });

  factory WalkPrompt.fromStop(WalkedStop stop) => WalkPrompt(
    stopId: stop.stopId,
    stopName: stop.stopName,
    prompt: stop.prompt,
    reachedAt: stop.reachedAt,
  );
}

// A photo the user picked but hasn't saved yet. Made by
// WalkPhotoService.preparePhoto, which checks the image when it's picked, so
// a bad file is rejected right away rather than at Save. [photoId] is
// assigned up front, so retrying a failed save reuses the same ID and
// storage path.
class PendingPhoto {
  final String photoId;
  final Uint8List bytes;
  final String contentType;
  final String? stopId;

  // Only for display in the editor (e.g. the picker's file name). Not stored.
  final String? fileName;

  const PendingPhoto({
    required this.photoId,
    required this.bytes,
    required this.contentType,
    this.stopId,
    this.fileName,
  });

  int get sizeBytes => bytes.lengthInBytes;

  PendingPhoto withStop(String? newStopId) => PendingPhoto(
    photoId: photoId,
    bytes: bytes,
    contentType: contentType,
    stopId: newStopId,
    fileName: fileName,
  );
}

// Everything the Activity page needs to show one walk's photos next to
// their prompts.
class WalkPhotoGallery {
  final WalkedRoute walk;

  // In route order.
  final List<WalkPrompt> prompts;

  // Oldest upload first.
  final List<WalkPhoto> photos;

  WalkPhotoGallery({
    required this.walk,
    required List<WalkPrompt> prompts,
    required List<WalkPhoto> photos,
  }) : prompts = List.unmodifiable(prompts),
       photos = List.unmodifiable(photos);

  // Photos for one stop's prompt, or with no prompt when [stopId] is null.
  List<WalkPhoto> photosForStop(String? stopId) =>
      photos.where((photo) => photo.stopId == stopId).toList();

  List<WalkPhoto> get unassigned => photosForStop(null);

  WalkPrompt? promptFor(WalkPhoto photo) {
    for (final prompt in prompts) {
      if (prompt.stopId == photo.stopId) return prompt;
    }
    return null;
  }
}
