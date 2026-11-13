// Widget tests for the minimal photo screens, using the same fakes as the
// backend tests. The picker is replaced by a function that returns bytes.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/walk_photo_service.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/frontend/screens/walk_gallery_page.dart';
import 'package:frame_walk/frontend/utils/photo_picker.dart';
import 'package:frame_walk/frontend/widgets/completed_walks_list.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/fake_photo_storage.dart';

// A real 1x1 PNG, so Image.memory can decode it.
final Uint8List png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  const uid = 'user-1';
  const walkId = 'walk-a';

  late FakeFirebaseFirestore firestore;
  late FakePhotoStorage storage;
  late MockFirebaseAuth auth;
  late WalkPhotoService service;
  late List<PickedPhoto> toPick;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    storage = FakePhotoStorage();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    service = WalkPhotoService(
      auth: auth,
      firestore: firestore,
      storage: storage,
    );
    toPick = [];
    final walk = WalkedRoute(
      id: walkId,
      userId: uid,
      routeId: 'red',
      routeTitle: 'Red Square Walk',
      status: WalkStatus.completed,
      startedAt: DateTime(2026, 11, 10, 9),
      completedAt: DateTime(2026, 11, 10, 10),
      stops: const [
        WalkedStop(
          stopId: 'red_1',
          stopName: 'Red Square',
          latitude: 47.6559,
          longitude: -122.3078,
          prompt: 'Find a pattern.',
        ),
        WalkedStop(
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
        .doc(uid)
        .collection('walks')
        .doc(walkId)
        .set(walk.toMap());
  });

  Future<void> openGallery(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalkGalleryPage(
          walkedRouteId: walkId,
          service: service,
          pickPhotos: () async => toPick,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseStop(WidgetTester tester, int row, String label) async {
    await tester.tap(find.byType(DropdownButton<String>).at(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('gallery groups photos by prompt, with a No prompt group', (
    tester,
  ) async {
    await tester.runAsync(
      () => service.uploadPhotos(walkId, [
        service.preparePhoto(png, stopId: 'red_1'),
        service.preparePhoto(png, stopId: 'red_1'),
        service.preparePhoto(png),
      ]),
    );
    await openGallery(tester);

    expect(find.text('Red Square Walk'), findsOneWidget);
    expect(find.text('Red Square (2)'), findsOneWidget);
    expect(find.text('Find a pattern.'), findsOneWidget);
    expect(find.text('Suzzallo Library (0)'), findsOneWidget);
    expect(find.text('No prompt (1)'), findsOneWidget);
    expect(find.text('Add / edit photos'), findsOneWidget);
  });

  testWidgets('add photos, tag them, reject a bad file, and save', (
    tester,
  ) async {
    await openGallery(tester);
    expect(find.text('No prompt (0)'), findsOneWidget);

    toPick = [
      PickedPhoto(png, 'a.png'),
      PickedPhoto(png, 'b.png'),
      PickedPhoto(Uint8List.fromList('not an image'.codeUnits), 'notes.txt'),
    ];
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not added'), findsOneWidget);
    expect(find.textContaining('notes.txt'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    expect(storage.uploadCalls, isEmpty); // Nothing uploads before Save.

    await chooseStop(tester, 0, 'Red Square: Find a pattern.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Photos saved'), findsOneWidget);
    expect(find.text('Red Square (1)'), findsOneWidget);
    expect(find.text('No prompt (1)'), findsOneWidget);
    expect(storage.files, hasLength(2));
  });

  testWidgets('a photo removed before saving is never uploaded', (
    tester,
  ) async {
    await openGallery(tester);
    toPick = [PickedPhoto(png, 'a.png')];
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove photo'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(storage.uploadCalls, isEmpty);
  });

  testWidgets('a failed upload stays staged and can be retried', (
    tester,
  ) async {
    await openGallery(tester);
    toPick = [PickedPhoto(png, 'a.png')];
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();

    storage.failAllUploads = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Some changes were not saved'), findsOneWidget);
    expect(find.textContaining('Upload failed'), findsOneWidget);
    expect(find.text('Retry failed changes (1)'), findsOneWidget);

    storage.failAllUploads = false;
    await tester.tap(find.text('Retry failed changes (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Photos saved'), findsOneWidget);
    expect(find.text('No prompt (1)'), findsOneWidget);
  });

  testWidgets('changing and deleting saved photos', (tester) async {
    await tester.runAsync(
      () => service.uploadPhotos(walkId, [
        service.preparePhoto(png),
        service.preparePhoto(png),
      ]),
    );
    await openGallery(tester);
    await tester.tap(find.text('Add / edit photos'));
    await tester.pumpAndSettle();

    await chooseStop(tester, 0, 'Suzzallo Library: Light and shadow.');
    await tester.tap(find.byTooltip('Remove photo').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('will be removed from FrameWalk'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Suzzallo Library (1)'), findsOneWidget);
    expect(find.text('No prompt (0)'), findsOneWidget);
    expect(storage.files, hasLength(1));
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await openGallery(tester);
    toPick = [PickedPhoto(png, 'a.png')];
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('No prompt (0)'), findsOneWidget);
    expect(storage.uploadCalls, isEmpty);
  });

  testWidgets('previous walks list shows completed walks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompletedWalksList(
            auth: auth,
            repository: WalkRepository(firestore: firestore),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Red Square Walk'), findsOneWidget);
    expect(find.textContaining('2 stops'), findsOneWidget);
  });

  testWidgets('previous walks list is empty when signed out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompletedWalksList(
            auth: MockFirebaseAuth(),
            repository: WalkRepository(firestore: firestore),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No previous walks yet.'), findsOneWidget);
  });
}
