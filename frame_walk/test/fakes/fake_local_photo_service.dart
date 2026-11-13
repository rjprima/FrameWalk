import 'dart:async';
import 'dart:typed_data';

import 'package:frame_walk/backend/services/local_photo_service.dart';
import 'package:frame_walk/models/gallery_photo.dart';
import 'package:frame_walk/models/mock_route_data.dart';
import 'package:frame_walk/models/walk_record.dart';

// An in-memory camera roll for tests. Like the real service, it can only
// read photos; there's no way to delete or change them.
class FakeLocalPhotoService implements LocalPhotoService {
  GalleryAccess access;

  // What requestAccess() changes [access] to, like the user's answer to the
  // system prompt.
  GalleryAccess accessAfterRequest;

  final List<GalleryPhoto> gallery;
  final Set<String> unreadableThumbnails = {};
  String installId;

  @override
  String platformName = 'android';

  int checkAccessCalls = 0;
  int requestAccessCalls = 0;
  int openSettingsCalls = 0;
  int manageSelectionCalls = 0;
  int galleryQueries = 0;
  final List<int> requestedPages = [];

  final _changes = StreamController<void>.broadcast();

  FakeLocalPhotoService({
    this.access = GalleryAccess.full,
    GalleryAccess? accessAfterRequest,
    List<GalleryPhoto>? gallery,
    this.installId = 'install-a',
  })  : accessAfterRequest = accessAfterRequest ?? access,
        gallery = gallery ?? [];

  void deletePhotoOutsideApp(String assetId) {
    gallery.removeWhere((photo) => photo.assetId == assetId);
    _changes.add(null);
  }

  @override
  Future<GalleryAccess> checkAccess() async {
    checkAccessCalls++;
    return access;
  }

  @override
  Future<GalleryAccess> requestAccess() async {
    requestAccessCalls++;
    return access = accessAfterRequest;
  }

  @override
  Future<void> openAccessSettings() async => openSettingsCalls++;

  @override
  Future<void> manageLimitedSelection() async => manageSelectionCalls++;

  @override
  Future<String> deviceInstallId() async => installId;

  @override
  Future<GalleryPage> fetchPhotos({
    required int page,
    required int pageSize,
  }) async {
    galleryQueries++;
    requestedPages.add(page);
    if (!access.canRead) {
      return GalleryPage(photos: const [], page: page, hasMore: false);
    }
    final newestFirst = [...gallery]
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, newestFirst.length);
    final photos =
        start >= newestFirst.length ? <GalleryPhoto>[] : newestFirst.sublist(start, end);
    return GalleryPage(
      photos: photos,
      page: page,
      hasMore: end < newestFirst.length,
    );
  }

  @override
  Future<List<GalleryPhoto>> fetchPhotosTakenBetween(
    DateTime start,
    DateTime end,
  ) async {
    galleryQueries++;
    if (!access.canRead) return [];
    return gallery
        .where((p) => !p.takenAt.isBefore(start) && !p.takenAt.isAfter(end))
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  @override
  Future<GalleryPhoto?> findPhoto(String assetId) async {
    if (!access.canRead) return null;
    for (final photo in gallery) {
      if (photo.assetId == assetId) return photo;
    }
    return null;
  }

  @override
  Future<Uint8List?> loadThumbnail(String assetId, {int size = 256}) async {
    if (unreadableThumbnails.contains(assetId)) return null;
    final exists = gallery.any((photo) => photo.assetId == assetId);
    return exists ? transparentPng : null;
  }

  @override
  Stream<void> get changes => _changes.stream;
}

// A valid 1x1 transparent PNG.
final transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

// Shared fixtures: a 40-minute Red Square walk on Nov 1, 2026.
final walkStart = DateTime(2026, 11, 1, 10, 0);
final walkEnd = DateTime(2026, 11, 1, 10, 40);

WalkRecord redSquareWalk({String id = 'walk-1', String userId = 'user-1'}) {
  return WalkRecord.fromRoute(
    userId: userId,
    routeId: '1',
    routeTitle: 'Red Square Walk',
    stops: MockRouteData.redSquareStops,
    startedAt: walkStart,
    completedAt: walkEnd,
  ).withId(id);
}

// Red Square stop 1 and stop 2 (Suzzallo Library) coordinates.
const redSquare = GeoCoordinate(47.6559, -122.3078);
const suzzallo = GeoCoordinate(47.6553, -122.3099);

GalleryPhoto photoAt(
  String assetId,
  DateTime takenAt, {
  GeoCoordinate? location,
  int width = 4000,
  int height = 3000,
}) {
  return GalleryPhoto(
    assetId: assetId,
    takenAt: takenAt,
    width: width,
    height: height,
    location: location,
  );
}
