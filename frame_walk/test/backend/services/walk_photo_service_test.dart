// Unit tests for WalkPhotoService using fakes: FakeFirebaseFirestore,
// MockFirebaseAuth, and an in-memory FakePhotoStorage. They don't touch
// Firebase. The rules and the real SDKs are covered by
// integration_test/walk_photo_service_emulator_test.dart.
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/image_validation.dart';
import 'package:frame_walk/backend/services/walk_photo_service.dart';
import 'package:frame_walk/models/walk_photo.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/failing_firestore.dart';
import '../../fakes/fake_photo_storage.dart';

void main() {
  const uid = 'user-1';
  const otherUid = 'user-2';
  final now = DateTime(2026, 11, 12, 15);

  late FailingBatchFirestore firestore;
  late FakePhotoStorage storage;
  late MockFirebaseAuth auth;
  late WalkPhotoService service;

  Uint8List jpeg([int size = 64]) {
    final bytes = Uint8List(size);
    bytes.setAll(0, [0xFF, 0xD8, 0xFF, 0xE0]);
    return bytes;
  }

  WalkPhotoService serviceFor(MockFirebaseAuth auth) => WalkPhotoService(
    auth: auth,
    firestore: firestore,
    storage: storage,
    clock: () => now,
  );

  // Saves a walk directly, as WalkRepository would after completeWalk.
  Future<WalkedRoute> seedWalk(
    String id, {
    String userId = uid,
    String routeId = 'red',
    WalkStatus status = WalkStatus.completed,
    List<WalkedStop>? stops,
  }) async {
    final walk = WalkedRoute(
      id: id,
      userId: userId,
      routeId: routeId,
      routeTitle: 'Red Square Walk',
      status: status,
      startedAt: DateTime(2026, 11, 10, 9),
      completedAt: status == WalkStatus.completed
          ? DateTime(2026, 11, 10, 10)
          : null,
      stops:
          stops ??
          [
            WalkedStop(
              stopId: 'red_1',
              stopName: 'Red Square',
              latitude: 47.6559,
              longitude: -122.3078,
              prompt: 'Find a pattern.',
              reachedAt: DateTime(2026, 11, 10, 9, 10),
            ),
            const WalkedStop(
              stopId: 'red_2',
              stopName: 'Suzzallo Library',
              latitude: 47.6553,
              longitude: -122.3099,
              prompt: 'Light and shadow.',
            ),
          ],
    );
    await firestore
        .collection('users')
        .doc(userId)
        .collection('walks')
        .doc(id)
        .set(walk.toMap());
    return walk;
  }

  Future<List<Map<String, dynamic>>> photoDocs(
    String walkId, {
    String userId = uid,
  }) async {
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('walks')
        .doc(walkId)
        .collection('photos')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  String pathOf(String walkId, String photoId) =>
      WalkPhotoService.storagePathFor(uid, walkId, photoId);

  setUp(() {
    firestore = FailingBatchFirestore();
    storage = FakePhotoStorage();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    service = serviceFor(auth);
  });

  group('retrieving', () {
    test('a walk with no photos has an empty list', () async {
      await seedWalk('walk-a');
      expect(await service.fetchPhotos('walk-a'), isEmpty);
      final gallery = await service.fetchGallery('walk-a');
      expect(gallery.photos, isEmpty);
      expect(gallery.prompts, hasLength(2));
    });

    test('returns photos with their prompt association', () async {
      await seedWalk('walk-a');
      await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_2'),
      ]);

      final gallery = await service.fetchGallery('walk-a');
      expect(gallery.photos, hasLength(1));
      final photo = gallery.photos.single;
      expect(photo.stopId, 'red_2');
      expect(gallery.promptFor(photo)!.prompt, 'Light and shadow.');
    });

    test(
      'a missing or malformed walk ID is reported as walkNotFound',
      () async {
        for (final id in ['', 'nope', 'a/b', '../x']) {
          await expectLater(
            service.fetchPhotos(id),
            throwsA(
              isA<PhotoFailure>().having(
                (f) => f.code,
                'code',
                PhotoErrorCode.walkNotFound,
              ),
            ),
          );
        }
      },
    );

    test('the prompts are the ones this walk showed, in order', () async {
      await seedWalk('walk-a');
      // Same route walked again after its prompt changed.
      await seedWalk(
        'walk-b',
        stops: const [
          WalkedStop(
            stopId: 'red_1',
            stopName: 'Red Square',
            latitude: 47.6559,
            longitude: -122.3078,
            prompt: 'Something blue.',
          ),
        ],
      );

      final a = await service.fetchPrompts('walk-a');
      expect(a.map((p) => p.stopId), ['red_1', 'red_2']);
      expect(a.map((p) => p.prompt), ['Find a pattern.', 'Light and shadow.']);
      expect(a.first.reachedAt, isNotNull);
      expect(a.last.reachedAt, isNull);

      final b = await service.fetchPrompts('walk-b');
      expect(b.map((p) => p.prompt), ['Something blue.']);
    });

    test('loads image bytes and URLs for the owner', () async {
      await seedWalk('walk-a');
      final bytes = jpeg(100);
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(bytes),
      ]);
      expect(await service.loadPhotoBytes(photo), bytes);
      expect(await service.photoDownloadUrl(photo), contains(photo.photoId));
    });
  });

  group('preparing photos', () {
    test('detects the real image type from the bytes', () {
      final photo = service.preparePhoto(jpeg(), fileName: 'IMG_1.PNG');
      expect(photo.contentType, 'image/jpeg');
      expect(photo.photoId, isNotEmpty);
    });

    test('rejects files that are not images', () {
      expect(
        () => service.preparePhoto(Uint8List.fromList('hello'.codeUnits)),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.invalidImage,
          ),
        ),
      );
      expect(
        () => service.preparePhoto(Uint8List(0)),
        throwsA(isA<PhotoFailure>()),
      );
    });

    test('rejects images over the size limit', () {
      expect(
        () => service.preparePhoto(jpeg(ImageValidation.maxBytes + 1)),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.imageTooLarge,
          ),
        ),
      );
    });

    test('gives each photo a unique ID', () {
      final ids = {
        for (var i = 0; i < 20; i++) service.preparePhoto(jpeg()).photoId,
      };
      expect(ids, hasLength(20));
    });
  });

  group('uploading', () {
    test('uploads one photo to Storage and records it in Firestore', () async {
      await seedWalk('walk-a');
      final pending = service.preparePhoto(jpeg(200), stopId: 'red_1');

      final [photo] = await service.uploadPhotos('walk-a', [pending]);

      final path = pathOf('walk-a', pending.photoId);
      expect(storage.files[path]!.bytes, pending.bytes);
      expect(storage.files[path]!.contentType, 'image/jpeg');
      expect(photo.storagePath, path);

      final [doc] = await photoDocs('walk-a');
      expect(doc['photoId'], pending.photoId);
      expect(doc['userId'], uid);
      expect(doc['walkedRouteId'], 'walk-a');
      expect(doc['storagePath'], path);
      expect(doc['stopId'], 'red_1');
      expect(doc['contentType'], 'image/jpeg');
      expect(doc['sizeBytes'], 200);
      expect(doc.containsKey('bytes'), isFalse);
    });

    test('uploads several photos, including several for one stop', () async {
      await seedWalk('walk-a');
      final photos = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
        service.preparePhoto(jpeg(), stopId: 'red_1'),
        service.preparePhoto(jpeg(), stopId: 'red_1'),
        service.preparePhoto(jpeg(), stopId: 'red_2'),
      ]);

      expect(photos, hasLength(4));
      expect(storage.files, hasLength(4));
      final gallery = await service.fetchGallery('walk-a');
      expect(gallery.photosForStop('red_1'), hasLength(3));
      expect(gallery.photosForStop('red_2'), hasLength(1));
    });

    test('uploads a photo with no prompt', () async {
      await seedWalk('walk-a');
      await service.uploadPhotos('walk-a', [service.preparePhoto(jpeg())]);

      final gallery = await service.fetchGallery('walk-a');
      expect(gallery.unassigned, hasLength(1));
      expect(gallery.promptFor(gallery.unassigned.single), isNull);
      expect((await photoDocs('walk-a')).single['stopId'], isNull);
    });

    test('reports upload progress', () async {
      await seedWalk('walk-a');
      final updates = <SaveProgress>[];
      await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(100)),
        service.preparePhoto(jpeg(300)),
      ], onProgress: updates.add);
      expect(updates.last.photosUploaded, 2);
      expect(updates.last.bytesSent, 400);
      expect(updates.last.fraction, 1);
    });

    test(
      'rejects a stop from another walk before uploading anything',
      () async {
        await seedWalk('walk-a');
        await seedWalk(
          'walk-b',
          routeId: 'blue',
          stops: const [
            WalkedStop(
              stopId: 'blue_1',
              stopName: 'Fountain',
              latitude: 47.65,
              longitude: -122.30,
            ),
          ],
        );

        await expectLater(
          service.uploadPhotos('walk-a', [
            service.preparePhoto(jpeg(), stopId: 'blue_1'),
          ]),
          throwsA(
            isA<PhotoFailure>().having(
              (f) => f.code,
              'code',
              PhotoErrorCode.invalidStop,
            ),
          ),
        );
        expect(storage.uploadCalls, isEmpty);
        expect(await photoDocs('walk-a'), isEmpty);
      },
    );

    test('only finished walks accept photos', () async {
      await seedWalk('walk-a', status: WalkStatus.active);
      await expectLater(
        service.uploadPhotos('walk-a', [service.preparePhoto(jpeg())]),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.walkNotCompleted,
          ),
        ),
      );
      expect(storage.uploadCalls, isEmpty);
    });

    test('rejects photos that were not prepared by preparePhoto', () async {
      await seedWalk('walk-a');
      final forged = PendingPhoto(
        photoId: 'abc',
        bytes: Uint8List.fromList('<svg/>'.codeUnits),
        contentType: 'image/jpeg',
      );
      await expectLater(
        service.uploadPhotos('walk-a', [forged]),
        throwsA(isA<PhotoFailure>()),
      );
      expect(storage.uploadCalls, isEmpty);
    });

    test('requires a signed-in user', () async {
      await seedWalk('walk-a');
      final signedOut = serviceFor(MockFirebaseAuth());
      await expectLater(
        signedOut.fetchPhotos('walk-a'),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.notSignedIn,
          ),
        ),
      );
    });
  });

  group('editing associations', () {
    test('changes the prompt without re-uploading', () async {
      await seedWalk('walk-a');
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
      ]);
      storage.uploadCalls.clear();

      final updated = await service.updatePhotoStop(
        'walk-a',
        photo.photoId,
        'red_2',
      );

      expect(updated.stopId, 'red_2');
      expect(storage.uploadCalls, isEmpty);
      expect((await photoDocs('walk-a')).single['stopId'], 'red_2');
    });

    test('can set a photo to No prompt', () async {
      await seedWalk('walk-a');
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
      ]);
      await service.updatePhotoStop('walk-a', photo.photoId, null);
      expect((await service.fetchGallery('walk-a')).unassigned, hasLength(1));
    });

    test('rejects a stop belonging to another walked route', () async {
      await seedWalk('walk-a');
      await seedWalk(
        'walk-b',
        stops: const [
          WalkedStop(
            stopId: 'other_stop',
            stopName: 'Elsewhere',
            latitude: 0,
            longitude: 0,
          ),
        ],
      );
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
      ]);

      await expectLater(
        service.updatePhotoStop('walk-a', photo.photoId, 'other_stop'),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.invalidStop,
          ),
        ),
      );
      expect((await photoDocs('walk-a')).single['stopId'], 'red_1');
    });

    test('editing a photo that does not exist fails', () async {
      await seedWalk('walk-a');
      await expectLater(
        service.updatePhotoStop('walk-a', 'ghost', 'red_1'),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.photoNotFound,
          ),
        ),
      );
    });
  });

  group('deleting', () {
    test('removes the metadata and the file', () async {
      await seedWalk('walk-a');
      final [photo, keep] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg()),
        service.preparePhoto(jpeg()),
      ]);

      await service.deletePhoto('walk-a', photo.photoId);

      final remaining = await service.fetchPhotos('walk-a');
      expect(remaining.map((p) => p.photoId), [keep.photoId]);
      expect(storage.files.keys, [keep.storagePath]);
    });

    test('deleting a photo that is already gone succeeds', () async {
      await seedWalk('walk-a');
      await service.deletePhoto('walk-a', 'never-existed');
    });

    test('succeeds when the file is already missing from Storage', () async {
      await seedWalk('walk-a');
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg()),
      ]);
      storage.files.clear();

      final result = await service.saveChanges(
        'walk-a',
        PhotoChangeSet()..remove(photo.photoId),
      );
      expect(result.isComplete, isTrue);
      expect(result.orphanedStoragePaths, isEmpty);
      expect(await photoDocs('walk-a'), isEmpty);
    });

    test('a file that cannot be removed is reported, not hidden', () async {
      await seedWalk('walk-a');
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg()),
      ]);
      storage.failDeletes.add(photo.storagePath);

      final result = await service.saveChanges(
        'walk-a',
        PhotoChangeSet()..remove(photo.photoId),
      );
      // Gone for the user; the leftover file is reported for cleanup.
      expect(result.isComplete, isTrue);
      expect(result.deletedPhotoIds, [photo.photoId]);
      expect(result.orphanedStoragePaths, [photo.storagePath]);
      expect(await photoDocs('walk-a'), isEmpty);
    });

    test('loading a deleted photo reports photoNotFound', () async {
      await seedWalk('walk-a');
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg()),
      ]);
      storage.files.clear();
      await expectLater(
        service.loadPhotoBytes(photo),
        throwsA(
          isA<PhotoFailure>().having(
            (f) => f.code,
            'code',
            PhotoErrorCode.photoNotFound,
          ),
        ),
      );
    });
  });

  group('staged saving', () {
    test('saves additions, edits and deletions together', () async {
      await seedWalk('walk-a');
      final [edit, drop] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
        service.preparePhoto(jpeg()),
      ]);

      final changes = PhotoChangeSet()
        ..add(service.preparePhoto(jpeg(), stopId: 'red_2'))
        ..add(service.preparePhoto(jpeg(), stopId: 'red_2'))
        ..add(service.preparePhoto(jpeg()))
        ..setStop(edit.photoId, null)
        ..remove(drop.photoId);

      final result = await service.saveChanges('walk-a', changes);

      expect(result.isComplete, isTrue);
      expect(result.errors, isEmpty);
      expect(result.added, hasLength(3));
      expect(result.updatedPhotoIds, [edit.photoId]);
      expect(result.deletedPhotoIds, [drop.photoId]);
      expect(result.photos, hasLength(4));

      final gallery = await service.fetchGallery('walk-a');
      expect(gallery.photosForStop('red_2'), hasLength(2));
      expect(gallery.unassigned, hasLength(2));
      expect(storage.files.containsKey(drop.storagePath), isFalse);
    });

    test('nothing is uploaded until saveChanges', () async {
      await seedWalk('walk-a');
      final changes = PhotoChangeSet()
        ..add(service.preparePhoto(jpeg()))
        ..add(service.preparePhoto(jpeg()));
      expect(storage.uploadCalls, isEmpty);
      expect(changes.changeCount, 2);
    });

    test('change set: removing or re-tagging a new photo stays local', () {
      final changes = PhotoChangeSet();
      final a = service.preparePhoto(jpeg());
      changes
        ..add(a)
        ..setStop(a.photoId, 'red_1');
      expect(changes.additions.single.stopId, 'red_1');
      expect(changes.stopChanges, isEmpty);

      changes.remove(a.photoId);
      expect(changes.isEmpty, isTrue);

      changes
        ..setStop('saved-1', 'red_1')
        ..remove('saved-1')
        ..setStop('saved-1', 'red_2');
      expect(changes.stopChanges, isEmpty);
      expect(changes.deletions, {'saved-1'});
    });

    test('a failed upload keeps the rest and defers deletions', () async {
      await seedWalk('walk-a');
      final [edit, drop] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
        service.preparePhoto(jpeg()),
      ]);
      final good = service.preparePhoto(jpeg(), stopId: 'red_1');
      final bad = service.preparePhoto(jpeg(), stopId: 'red_2');
      storage.failUploads.add(pathOf('walk-a', bad.photoId));

      final changes = PhotoChangeSet()
        ..add(good)
        ..add(bad)
        ..setStop(edit.photoId, 'red_2')
        ..remove(drop.photoId);
      final result = await service.saveChanges('walk-a', changes);

      expect(result.isComplete, isFalse);
      expect(result.errors.single.code, PhotoErrorCode.uploadFailed);
      expect(result.errors.single.photoId, bad.photoId);
      expect(result.added.map((p) => p.photoId), [good.photoId]);
      expect(result.updatedPhotoIds, [edit.photoId]);
      // The deletion waits until everything new is saved.
      expect(result.deletedPhotoIds, isEmpty);
      expect(result.remaining.additions.map((p) => p.photoId), [bad.photoId]);
      expect(result.remaining.deletions, {drop.photoId});
      expect(storage.files.containsKey(drop.storagePath), isTrue);
      expect(() => result.throwIfIncomplete(), throwsA(isA<PhotoFailure>()));

      // Retrying just the remaining changes finishes the save.
      storage.failUploads.clear();
      final retry = await service.saveChanges('walk-a', result.remaining);
      expect(retry.isComplete, isTrue);
      final ids = (await service.fetchPhotos('walk-a')).map((p) => p.photoId);
      expect(ids, unorderedEquals([edit.photoId, good.photoId, bad.photoId]));
      expect(storage.files.containsKey(drop.storagePath), isFalse);
    });

    test('a failed Firestore write cleans up the uploaded files', () async {
      await seedWalk('walk-a');
      final [existing] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg()),
      ]);
      final changes = PhotoChangeSet()
        ..add(service.preparePhoto(jpeg()))
        ..add(service.preparePhoto(jpeg()))
        ..remove(existing.photoId);
      firestore.failBatchCommits = 1;

      final result = await service.saveChanges('walk-a', changes);

      expect(result.isComplete, isFalse);
      expect(result.errors.single.code, PhotoErrorCode.databaseFailed);
      expect(result.added, isEmpty);
      expect(result.remaining.changeCount, 3);
      // Only the photo that was there before is left, file and metadata.
      expect(storage.files.keys, [existing.storagePath]);
      expect((await photoDocs('walk-a')).single['photoId'], existing.photoId);
      expect(result.orphanedStoragePaths, isEmpty);

      final retry = await service.saveChanges('walk-a', result.remaining);
      expect(retry.isComplete, isTrue);
      expect(await photoDocs('walk-a'), hasLength(2));
    });

    test('a failed deletion is left to retry', () async {
      await seedWalk('walk-a');
      final [photo] = await service.uploadPhotos('walk-a', [
        service.preparePhoto(jpeg()),
      ]);
      firestore.failBatchCommits = 1;

      final result = await service.saveChanges(
        'walk-a',
        PhotoChangeSet()..remove(photo.photoId),
      );
      expect(result.isComplete, isFalse);
      expect(result.remaining.deletions, {photo.photoId});
      expect(storage.files.containsKey(photo.storagePath), isTrue);
      await expectLater(
        service.deletePhoto('walk-a', photo.photoId),
        completes,
      );
    });

    test('retrying a photo that already saved does not duplicate it', () async {
      await seedWalk('walk-a');
      final pending = service.preparePhoto(jpeg(), stopId: 'red_1');
      final changes = PhotoChangeSet()..add(pending);
      await service.saveChanges('walk-a', changes);
      storage.uploadCalls.clear();

      final again = await service.saveChanges('walk-a', changes);
      expect(again.isComplete, isTrue);
      expect(storage.uploadCalls, isEmpty);
      expect(await photoDocs('walk-a'), hasLength(1));
    });
  });

  group('ownership and separation', () {
    test("another user's walk and photos are not reachable", () async {
      await seedWalk('walk-x', userId: otherUid);
      final otherService = serviceFor(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: otherUid)),
      );
      final [theirs] = await otherService.uploadPhotos('walk-x', [
        otherService.preparePhoto(jpeg()),
      ]);

      final notFound = throwsA(
        isA<PhotoFailure>().having(
          (f) => f.code,
          'code',
          PhotoErrorCode.walkNotFound,
        ),
      );
      await expectLater(service.fetchPhotos('walk-x'), notFound);
      await expectLater(service.fetchPrompts('walk-x'), notFound);
      await expectLater(
        service.uploadPhotos('walk-x', [service.preparePhoto(jpeg())]),
        notFound,
      );
      await expectLater(
        service.deletePhoto('walk-x', theirs.photoId),
        notFound,
      );
      await expectLater(
        service.loadPhotoBytes(theirs),
        throwsA(isA<PhotoFailure>()),
      );

      expect(await photoDocs('walk-x', userId: otherUid), hasLength(1));
      expect(storage.files.containsKey(theirs.storagePath), isTrue);
    });

    test('repeated walks of the same route keep separate photos', () async {
      await seedWalk('walk-monday', routeId: 'red');
      await seedWalk('walk-friday', routeId: 'red');

      final [monday] = await service.uploadPhotos('walk-monday', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
      ]);
      await service.uploadPhotos('walk-friday', [
        service.preparePhoto(jpeg(), stopId: 'red_1'),
        service.preparePhoto(jpeg(), stopId: 'red_1'),
      ]);

      final mondayPhotos = await service.fetchPhotos('walk-monday');
      final fridayPhotos = await service.fetchPhotos('walk-friday');
      expect(mondayPhotos.map((p) => p.photoId), [monday.photoId]);
      expect(fridayPhotos, hasLength(2));
      expect(
        fridayPhotos.every((p) => p.walkedRouteId == 'walk-friday'),
        isTrue,
      );

      // A photo ID from one walk can't be edited through the other.
      await expectLater(
        service.updatePhotoStop('walk-friday', monday.photoId, 'red_2'),
        throwsA(isA<PhotoFailure>()),
      );
    });
  });
}
