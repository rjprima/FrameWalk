// Integration test: WalkPhotoService with the real FlutterFire SDKs against the
// Firebase Emulator Suite (Auth, Firestore, Storage), checking
// firestore.rules and storage.rules as well. It uses a demo- project, which
// the emulators never connect to real Firebase, so production data is never
// touched.
//
// From frame_walk/, with a simulator or emulator running:
//
//   firebase emulators:exec --project demo-framewalk \
//     --only auth,firestore,storage \
//     "flutter test integration_test/walk_photo_service_emulator_test.dart -d <device>"
//
// On the Android emulator add --dart-define=EMULATOR_HOST=10.0.2.2.
//
// The timings printed here are emulator timings (local network). They show
// the overhead of the code, not real-world network performance.
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/auth_service.dart';
import 'package:frame_walk/backend/services/photo_storage.dart';
import 'package:frame_walk/backend/services/walk_photo_service.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/models/route_stop.dart';
import 'package:frame_walk/models/walked_route.dart';
import 'package:integration_test/integration_test.dart';

const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
const projectId = 'demo-framewalk';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseAuth auth;
  late FirebaseFirestore firestore;
  late FirebaseStorage storage;
  late WalkPhotoService service;
  late WalkRepository walks;
  final random = Random(7);
  final runId = DateTime.now().millisecondsSinceEpoch;

  // Bytes shaped like a JPEG. Random data doesn't compress, like real JPEG
  // data, so upload times are realistic for the size.
  Uint8List jpeg(int size) {
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      bytes[i] = random.nextInt(256);
    }
    bytes.setAll(0, [0xFF, 0xD8, 0xFF, 0xE0]);
    return bytes;
  }

  Future<String> signUp(String name) async {
    await auth.signOut();
    await AuthService(auth: auth, firestore: firestore).createAccount(
      email: '$name$runId@example.com',
      username: '$name${runId % 100000}',
      password: 'password123',
    );
    return auth.currentUser!.uid;
  }

  Future<WalkedRoute> finishedWalk(String uid, {String routeId = 'red'}) async {
    final walk = WalkedRoute.start(
      id: walks.newWalkId(uid),
      userId: uid,
      routeId: routeId,
      routeTitle: 'Red Square Walk',
      stops: [
        RouteStop(
          id: '${routeId}_1',
          name: 'Red Square',
          prompt: 'Find a pattern.',
          latitude: 47.6559,
          longitude: -122.3078,
        ),
        RouteStop(
          id: '${routeId}_2',
          name: 'Suzzallo',
          prompt: 'Light and shadow.',
          latitude: 47.6553,
          longitude: -122.3099,
        ),
      ],
      startedAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    await walks.createWalk(walk);
    final done = walk.copyWith(
      status: WalkStatus.completed,
      completedAt: DateTime.now(),
    );
    await walks.completeWalk(done);
    return done;
  }

  DocumentReference<Map<String, dynamic>> photoDoc(
    String uid,
    String walkId,
    String photoId,
  ) => firestore.doc('users/$uid/walks/$walkId/photos/$photoId');

  Matcher deniedFirebase() => throwsA(
    isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'),
  );

  setUpAll(() async {
    final app = await Firebase.initializeApp(
      name: 'emulator-test',
      options: const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:952755882028:ios:3487de7547042a9c87e989',
        messagingSenderId: '952755882028',
        projectId: projectId,
        storageBucket: '$projectId.appspot.com',
      ),
    );
    auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator(host, 9099);
    firestore = FirebaseFirestore.instanceFor(app: app);
    firestore.useFirestoreEmulator(host, 8080);
    firestore.settings = const Settings(persistenceEnabled: false);
    storage = FirebaseStorage.instanceFor(app: app);
    await storage.useStorageEmulator(host, 9199);
    walks = WalkRepository(firestore: firestore);
    service = WalkPhotoService(
      auth: auth,
      firestore: firestore,
      storage: FirebasePhotoStorage(storage: storage),
      walkRepository: walks,
    );
  });

  testWidgets('upload, retrieve, re-associate and delete through the real '
      'SDKs', (tester) async {
    final uid = await signUp('owner');
    final walk = await finishedWalk(uid);

    final prompts = await service.fetchPrompts(walk.id);
    expect(prompts.map((p) => p.stopId), ['red_1', 'red_2']);

    final photos = await service.uploadPhotos(walk.id, [
      service.preparePhoto(jpeg(200 * 1024), stopId: 'red_1'),
      service.preparePhoto(jpeg(200 * 1024), stopId: 'red_1'),
      service.preparePhoto(jpeg(100 * 1024)),
    ]);
    expect(photos, hasLength(3));

    final gallery = await service.fetchGallery(walk.id);
    expect(gallery.photosForStop('red_1'), hasLength(2));
    expect(gallery.unassigned, hasLength(1));
    final bytes = await service.loadPhotoBytes(gallery.unassigned.single);
    expect(bytes.length, 100 * 1024);

    await service.updatePhotoStop(walk.id, photos.first.photoId, 'red_2');
    await service.deletePhoto(walk.id, photos.last.photoId);
    final after = await service.fetchGallery(walk.id);
    expect(after.photos, hasLength(2));
    expect(after.photosForStop('red_2'), hasLength(1));
    await expectLater(
      storage.ref(photos.last.storagePath).getMetadata(),
      throwsA(isA<FirebaseException>()),
    );

    // A second walk of the same route keeps its own photos.
    final again = await finishedWalk(uid);
    expect(await service.fetchPhotos(again.id), isEmpty);
  });

  testWidgets('security rules enforce ownership and valid associations', (
    tester,
  ) async {
    final owner = await signUp('alice');
    final walk = await finishedWalk(owner);
    final other = await finishedWalk(owner, routeId: 'blue');
    final [photo] = await service.uploadPhotos(walk.id, [
      service.preparePhoto(jpeg(50 * 1024), stopId: 'red_1'),
    ]);

    // Writing Firestore directly, skipping the service's own checks:
    // a stop from another walk is refused by the rules.
    await expectLater(
      photoDoc(owner, walk.id, photo.photoId).update({
        'stopId': other.stops.first.stopId,
        'updatedAt': Timestamp.now(),
      }),
      deniedFirebase(),
    );
    // The storage path can't be changed.
    await expectLater(
      photoDoc(
        owner,
        walk.id,
        photo.photoId,
      ).update({'storagePath': 'users/$owner/somewhere/else'}),
      deniedFirebase(),
    );
    // Non-image uploads are refused by storage.rules.
    await expectLater(
      storage
          .ref(WalkPhotoService.storagePathFor(owner, walk.id, 'textfile'))
          .putData(
            Uint8List.fromList('hello'.codeUnits),
            SettableMetadata(contentType: 'text/plain'),
          ),
      throwsA(isA<FirebaseException>()),
    );

    // Another user can't read, change or delete any of it.
    final intruder = await signUp('mallory');
    expect(intruder, isNot(owner));
    await expectLater(
      photoDoc(owner, walk.id, photo.photoId).get(),
      deniedFirebase(),
    );
    await expectLater(
      firestore.collection('users/$owner/walks/${walk.id}/photos').get(),
      deniedFirebase(),
    );
    await expectLater(
      photoDoc(owner, walk.id, photo.photoId).delete(),
      deniedFirebase(),
    );
    await expectLater(
      storage.ref(photo.storagePath).getData(),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      storage.ref(photo.storagePath).delete(),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      storage
          .ref(WalkPhotoService.storagePathFor(owner, walk.id, 'planted'))
          .putData(jpeg(1024), SettableMetadata(contentType: 'image/jpeg')),
      throwsA(isA<FirebaseException>()),
    );
    // Through the service, it looks like the walk doesn't exist.
    await expectLater(
      service.fetchPhotos(walk.id),
      throwsA(
        isA<PhotoFailure>().having(
          (f) => f.code,
          'code',
          PhotoErrorCode.walkNotFound,
        ),
      ),
    );
  });

  testWidgets('measure save time (emulator)', (tester) async {
    final uid = await signUp('timer');
    final cases = <String, List<int>>{
      '1 x 1.5 MB': [1536 * 1024],
      '1 x 3.5 MB (typical 12 MP phone photo)': [3584 * 1024],
      '3 x 3.5 MB': List.filled(3, 3584 * 1024),
      '5 x 3.5 MB': List.filled(5, 3584 * 1024),
      '1 x 12 MB (camera JPEG)': [12 * 1024 * 1024],
    };
    for (final entry in cases.entries) {
      final walk = await finishedWalk(uid);
      final changes = PhotoChangeSet();
      for (final size in entry.value) {
        changes.add(service.preparePhoto(jpeg(size), stopId: 'red_1'));
      }
      final result = await service.saveChanges(walk.id, changes);
      expect(result.isComplete, isTrue, reason: '${result.errors}');
      // ignore: avoid_print
      print('TIMING ${entry.key}: ${result.timings}');
    }
  });
}
