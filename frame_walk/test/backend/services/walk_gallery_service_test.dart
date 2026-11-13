import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/local_photo_service.dart';
import 'package:frame_walk/backend/services/walk_gallery_service.dart';
import 'package:frame_walk/backend/services/walk_history_service.dart';
import 'package:frame_walk/models/walk_photo_link.dart';

import 'fakes/fake_local_photo_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late WalkHistoryService history;
  late FakeLocalPhotoService photos;
  late WalkGalleryService service;
  final walk = redSquareWalk();

  DateTime minutesIn(int minutes) => walkStart.add(Duration(minutes: minutes));

  setUp(() {
    firestore = FakeFirebaseFirestore();
    history = WalkHistoryService(firestore: firestore);
    photos = FakeLocalPhotoService();
    service = WalkGalleryService(photos: photos, history: history);
  });

  List<String> idsIn(List<WalkGalleryItem> items) =>
      items.map((item) => item.photo.assetId).toList();

  WalkGallerySection sectionFor(WalkGallery gallery, String stopId) =>
      gallery.sections.firstWhere((s) => s.stop.stopId == stopId);

  group('Permissions', () {
    test('does not read the gallery without access', () async {
      photos.access = GalleryAccess.denied;
      photos.gallery.add(photoAt('a', minutesIn(5)));

      final gallery = await service.loadGallery(walk);

      expect(gallery.access, GalleryAccess.denied);
      expect(gallery.hasVisiblePhotos, isFalse);
      expect(photos.galleryQueries, 0);
      expect(photos.requestAccessCalls, 0, reason: 'loading must not prompt');
    });

    test('works with limited access, showing only selected photos', () async {
      photos.access = GalleryAccess.limited;
      photos.gallery.add(photoAt('a', minutesIn(5), location: redSquare));

      final gallery = await service.loadGallery(walk);

      expect(gallery.access, GalleryAccess.limited);
      expect(idsIn(sectionFor(gallery, 'red_stop_1').items), ['a']);
    });
  });

  group('Matching photos to a walk', () {
    test('an empty camera roll gives an empty gallery', () async {
      final gallery = await service.loadGallery(walk);

      expect(gallery.hasVisiblePhotos, isFalse);
      expect(gallery.timeWindowPhotoCount, 0);
      expect(gallery.sections, hasLength(4), reason: 'one per prompt');
    });

    test('groups GPS-tagged photos by stop and suggests the rest', () async {
      photos.gallery.addAll([
        photoAt('at-red-square', minutesIn(2), location: redSquare),
        photoAt('at-suzzallo-1', minutesIn(12), location: suzzallo),
        photoAt('at-suzzallo-2', minutesIn(13), location: suzzallo),
        photoAt('no-gps', minutesIn(20)),
        photoAt('yesterday', walkStart.subtract(const Duration(days: 1)),
            location: redSquare),
      ]);

      final gallery = await service.loadGallery(walk);

      expect(idsIn(sectionFor(gallery, 'red_stop_1').items), ['at-red-square']);
      expect(idsIn(sectionFor(gallery, 'red_stop_2').items),
          ['at-suzzallo-1', 'at-suzzallo-2']);
      expect(idsIn(gallery.suggestions), ['no-gps']);
      expect(gallery.timeWindowPhotoCount, 4);
      expect(
        gallery.sections.expand((s) => s.items).every((i) => i.isSuggested),
        isTrue,
        reason: 'automatic matches are suggestions until the user acts',
      );
    });

    test('photos without GPS are suggested rather than placed', () async {
      photos.gallery.addAll([
        photoAt('a', minutesIn(5)),
        photoAt('b', minutesIn(30)),
      ]);

      final gallery = await service.loadGallery(walk);

      expect(idsIn(gallery.suggestions), ['a', 'b']);
      expect(gallery.sections.every((s) => s.items.isEmpty), isTrue);
    });
  });

  group('Manual associations', () {
    test('assigns one photo to a prompt', () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);

      await service.assignPhotos(walk, [photo], promptId: 'red_stop_3#0');
      final gallery = await service.loadGallery(walk);

      final section = sectionFor(gallery, 'red_stop_3');
      expect(idsIn(section.items), ['a']);
      expect(section.items.single.isSuggested, isFalse);
      expect(section.items.single.link!.stopId, 'red_stop_3');
      expect(gallery.suggestions, isEmpty);
    });

    test('assigns several photos to the same prompt', () async {
      final batch = [
        photoAt('a', minutesIn(5)),
        photoAt('b', minutesIn(6)),
        photoAt('c', minutesIn(7)),
      ];
      photos.gallery.addAll(batch);

      await service.assignPhotos(walk, batch, promptId: 'red_stop_1#0');
      final gallery = await service.loadGallery(walk);

      expect(idsIn(sectionFor(gallery, 'red_stop_1').items), ['a', 'b', 'c']);
    });

    test('adds photos taken outside the walk when chosen by hand', () async {
      final older = photoAt('older', walkStart.subtract(const Duration(days: 5)));
      photos.gallery.add(older);

      await service.assignPhotos(walk, [older], promptId: 'red_stop_4#0');
      final gallery = await service.loadGallery(walk);

      expect(idsIn(sectionFor(gallery, 'red_stop_4').items), ['older']);
    });

    test('keeps a photo with the walk but unassigned', () async {
      final photo = photoAt('a', minutesIn(5), location: redSquare);
      photos.gallery.add(photo);

      await service.assignPhotos(walk, [photo]);
      final gallery = await service.loadGallery(walk);

      expect(idsIn(gallery.unassigned), ['a']);
      expect(sectionFor(gallery, 'red_stop_1').items, isEmpty,
          reason: "the user's choice overrides GPS matching");
    });

    test('moves a photo from one prompt to another', () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);

      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');
      await service.assignPhotos(walk, [photo], promptId: 'red_stop_2#0');
      final gallery = await service.loadGallery(walk);

      expect(sectionFor(gallery, 'red_stop_1').items, isEmpty);
      expect(idsIn(sectionFor(gallery, 'red_stop_2').items), ['a']);
      final links = await history.fetchPhotoLinks('user-1', 'walk-1');
      expect(links, hasLength(1));
    });

    test('rejects a prompt that is not on the walk', () async {
      final photo = photoAt('a', minutesIn(5));
      expect(
        () => service.assignPhotos(walk, [photo], promptId: 'nature_stop_1#0'),
        throwsArgumentError,
      );
    });
  });

  group('Removing photos', () {
    test('removes a photo from the walk but not from the camera roll',
        () async {
      final photo = photoAt('a', minutesIn(5), location: redSquare);
      photos.gallery.add(photo);
      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');

      await service.removePhoto(walk, photo);
      final gallery = await service.loadGallery(walk);

      expect(gallery.hasVisiblePhotos, isFalse);
      expect(photos.gallery.map((p) => p.assetId), contains('a'));
      final links = await history.fetchPhotoLinks('user-1', 'walk-1');
      expect(links.single.status, PhotoLinkStatus.removed);
    });

    test('a removed suggestion is not suggested again', () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);

      await service.removePhoto(walk, photo);
      final gallery = await service.loadGallery(walk);

      expect(gallery.suggestions, isEmpty);
    });

    test('a removed photo can be added back', () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);
      await service.removePhoto(walk, photo);

      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');
      final gallery = await service.loadGallery(walk);

      expect(idsIn(sectionFor(gallery, 'red_stop_1').items), ['a']);
    });
  });

  group('Photos that are no longer available', () {
    test('reports a linked photo deleted from this device', () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);
      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');

      photos.deletePhotoOutsideApp('a');
      final gallery = await service.loadGallery(walk);

      expect(gallery.missing.single.assetId, 'a');
      expect(sectionFor(gallery, 'red_stop_1').items, isEmpty);
    });

    test('forgetting missing photos deletes only their links', () async {
      final gone = photoAt('gone', minutesIn(5));
      final kept = photoAt('kept', minutesIn(6));
      photos.gallery.addAll([gone, kept]);
      await service.assignPhotos(walk, [gone, kept], promptId: 'red_stop_1#0');
      photos.deletePhotoOutsideApp('gone');

      final before = await service.loadGallery(walk);
      await service.forgetMissingPhotos(before.missing);
      final after = await service.loadGallery(walk);

      expect(after.missing, isEmpty);
      expect(idsIn(sectionFor(after, 'red_stop_1').items), ['kept']);
    });

    test('photos linked on another device are counted, not called deleted',
        () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);
      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');

      // The same account on a new phone, where asset "a" doesn't exist.
      final otherPhone = FakeLocalPhotoService(installId: 'install-b');
      final gallery = await WalkGalleryService(
        photos: otherPhone,
        history: history,
      ).loadGallery(walk);

      expect(gallery.missing, isEmpty);
      expect(gallery.otherDeviceCount, 1);
    });

    test('ignores an asset ID that now belongs to a different photo',
        () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);
      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');

      // Another phone happens to have an unrelated photo with the same ID.
      final otherPhone = FakeLocalPhotoService(
        installId: 'install-b',
        gallery: [photoAt('a', DateTime(2020, 1, 1))],
      );
      final gallery = await WalkGalleryService(
        photos: otherPhone,
        history: history,
      ).loadGallery(walk);

      expect(sectionFor(gallery, 'red_stop_1').items, isEmpty);
      expect(gallery.otherDeviceCount, 1);
    });

    test('still finds photos after reinstalling on the same phone', () async {
      final photo = photoAt('a', minutesIn(5));
      photos.gallery.add(photo);
      await service.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');

      photos.installId = 'install-after-reinstall';
      final gallery = await service.loadGallery(walk);

      expect(idsIn(sectionFor(gallery, 'red_stop_1').items), ['a']);
    });
  });
}
