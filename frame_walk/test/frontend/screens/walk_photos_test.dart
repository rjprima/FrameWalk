import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frame_walk/backend/providers/profile_provider.dart';
import 'package:frame_walk/backend/services/auth_service.dart';
import 'package:frame_walk/backend/services/walk_photo_service.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/frontend/screens/route_past_walks_page.dart';
import 'package:frame_walk/frontend/screens/walk_gallery_page.dart';
import 'package:frame_walk/frontend/utils/photo_picker.dart';
import 'package:frame_walk/frontend/widgets/completed_walks_list.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/fake_photo_storage.dart';

// A real 1x1 PNG, so Image.memory can decode it.
final Uint8List png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

const uid = 'user-1';
const walkId = 'walk-a';

// Creates a ProfileProvider using the same fake Firebase instances as the test.
// Auth listening is disabled so each test controls when refresh() happens.
Future<ProfileProvider> createProfileProvider({
  required MockFirebaseAuth auth,
  required FakeFirebaseFirestore firestore,
}) async {
  final profile = ProfileProvider(
    authService: AuthService(auth: auth, firestore: firestore),
    walkRepository: WalkRepository(firestore: firestore),
    listenToAuthChanges: false,
  );

  await profile.refresh();
  return profile;
}

// Formats dates using the same localization rules as the app.
String formatTestDate(WidgetTester tester, DateTime date) {
  final context = tester.element(find.byType(Scaffold).first);

  return MaterialLocalizations.of(context).formatMediumDate(date);
}

// Creates another completed walk of the same route.
WalkedRoute createSecondWalk() {
  return WalkedRoute(
    id: 'walk-b',
    userId: uid,
    routeId: 'red',
    routeTitle: 'Red Square Walk',
    status: WalkStatus.completed,
    startedAt: DateTime(2026, 11, 12, 9),
    completedAt: DateTime(2026, 11, 12, 10),
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
}

Future<void> addSecondWalk(FakeFirebaseFirestore firestore) async {
  await firestore
      .collection('users')
      .doc(uid)
      .collection('walks')
      .doc('walk-b')
      .set(createSecondWalk().toMap());
}

void main() {
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

    // Saving photos updates the account's photosTaken count.
    // These fields also provide the data expected by UserAccount.fromMap().
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'username': 'walker',
      'email': 'walker@example.com',
      'routesCompleted': 1,
      'photosTaken': 0,
    });

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

  group('Walk gallery', () {
    testWidgets('groups photos by prompt, including No prompt', (tester) async {
      await tester.runAsync(
        () => service.uploadPhotos(walkId, [
          service.preparePhoto(png, stopId: 'red_1'),
          service.preparePhoto(png, stopId: 'red_1'),
          service.preparePhoto(png),
        ]),
      );

      await openGallery(tester);

      expect(
        find.text(formatTestDate(tester, DateTime(2026, 11, 10))),
        findsOneWidget,
      );
      expect(find.text('Red Square'), findsOneWidget);
      expect(find.text('Find a pattern.'), findsOneWidget);
      expect(find.text('Suzzallo Library'), findsOneWidget);
      expect(find.text('Light and shadow.'), findsOneWidget);
      expect(find.text('No prompt'), findsOneWidget);

      expect(find.text('Add / edit photos'), findsOneWidget);
    });

    testWidgets('shows an empty thumbnail placeholder for each empty group', (
      tester,
    ) async {
      await openGallery(tester);

      // There are two prompt groups and one No prompt group.
      expect(find.text('Red Square'), findsOneWidget);
      expect(find.text('Suzzallo Library'), findsOneWidget);
      expect(find.text('No prompt'), findsOneWidget);
      expect(find.text('No photos yet'), findsNWidgets(3));
    });

    testWidgets('add photos, tag them, reject a bad file, and save', (
      tester,
    ) async {
      await openGallery(tester);

      toPick = [
        PickedPhoto(png, 'a.png'),
        PickedPhoto(png, 'b.png'),
        PickedPhoto(Uint8List.fromList('not an image'.codeUnits), 'notes.txt'),
      ];

      // Open the editor using the gallery's floating action button.
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();

      // Open the image picker from the editor.
      await tester.tap(find.byTooltip('Add photos'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not added'), findsOneWidget);
      expect(find.textContaining('notes.txt'), findsOneWidget);

      // New photos display a generic label, not the generated filename.
      expect(find.text('New photo'), findsNWidgets(2));
      expect(find.text('a.png'), findsNothing);
      expect(find.text('b.png'), findsNothing);

      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
      expect(storage.uploadCalls, isEmpty);

      await chooseStop(tester, 0, 'Red Square: Find a pattern.');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Photos saved'), findsOneWidget);
      expect(find.text('Red Square'), findsOneWidget);
      expect(storage.files, hasLength(2));
    });

    testWidgets('prompt dropdown contains the complete prompt labels', (
      tester,
    ) async {
      await openGallery(tester);

      toPick = [PickedPhoto(png, 'a.png')];

      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add photos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('Red Square: Find a pattern.'), findsOneWidget);
      expect(find.text('Suzzallo Library: Light and shadow.'), findsOneWidget);
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

      expect(
        find.textContaining('Some changes were not saved'),
        findsOneWidget,
      );
      expect(find.textContaining('Upload failed'), findsOneWidget);
      expect(find.text('Retry failed changes (1)'), findsOneWidget);

      storage.failAllUploads = false;

      await tester.tap(find.text('Retry failed changes (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Photos saved'), findsOneWidget);
      expect(storage.files, hasLength(1));
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

      expect(find.text('Suzzallo Library'), findsOneWidget);
      expect(storage.files, hasLength(1));
    });

    testWidgets('leaving with unsaved changes asks before discarding', (
      tester,
    ) async {
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

      // The editor closes and the gallery remains visible.
      expect(find.text('No prompt'), findsOneWidget);
      expect(storage.uploadCalls, isEmpty);
    });
  });

  group('Completed walks list', () {
    testWidgets('shows each completed route once', (tester) async {
      await addSecondWalk(firestore);

      final profile = await createProfileProvider(
        auth: auth,
        firestore: firestore,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileProvider>.value(
          value: profile,
          child: const MaterialApp(home: Scaffold(body: CompletedWalksList())),
        ),
      );

      await tester.pumpAndSettle();

      // Both completed walks have the same routeId, so there is one card.
      expect(find.text('Red Square Walk'), findsOneWidget);
      expect(find.text('2 times'), findsOneWidget);
      expect(find.text('2 stops'), findsOneWidget);
      expect(find.textContaining('Last walked:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      profile.dispose();
    });

    testWidgets('shows the empty state when there are no completed walks', (
      tester,
    ) async {
      await firestore
          .collection('users')
          .doc(uid)
          .collection('walks')
          .doc(walkId)
          .delete();

      final profile = await createProfileProvider(
        auth: auth,
        firestore: firestore,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileProvider>.value(
          value: profile,
          child: const MaterialApp(home: Scaffold(body: CompletedWalksList())),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No previous walks yet.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      profile.dispose();
    });
  });

  group('Route past walks page', () {
    testWidgets('shows route summary and individual completed walks', (
      tester,
    ) async {
      await addSecondWalk(firestore);

      final profile = await createProfileProvider(
        auth: auth,
        firestore: firestore,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileProvider>.value(
          value: profile,
          child: MaterialApp(
            home: RoutePastWalksPage(
              routeId: 'red',
              routeTitle: 'Red Square Walk',
              photoService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Red Square Walk'), findsOneWidget);
      // Two individual completed walks each display their own stop count.
      expect(find.text('2 stops'), findsNWidgets(2));

      // The page header displays the overall route summary separately.
      expect(find.textContaining('2 stops  ·  Walked 2 times'), findsOneWidget);

      // Each completed walk has its own date and photo section.
      expect(
        find.text(formatTestDate(tester, DateTime(2026, 11, 12))),
        findsOneWidget,
      );
      expect(
        find.text(formatTestDate(tester, DateTime(2026, 11, 10))),
        findsOneWidget,
      );
      // Two individual completed walks each display their own stop count.
      expect(find.text('2 stops'), findsNWidgets(2));

      // The page header displays the overall route summary separately.
      expect(find.textContaining('2 stops  ·  Walked 2 times'), findsOneWidget);
      expect(find.text('No photos from this walk yet'), findsNWidgets(2));

      // The page header does not include a "Last walked" date.
      expect(find.textContaining('Last walked:'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      profile.dispose();
    });

    testWidgets('shows an empty state when the route has no completed walks', (
      tester,
    ) async {
      final profile = await createProfileProvider(
        auth: auth,
        firestore: firestore,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileProvider>.value(
          value: profile,
          child: MaterialApp(
            home: RoutePastWalksPage(
              routeId: 'different-route',
              routeTitle: 'Another Route',
              photoService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Another Route'), findsOneWidget);
      expect(find.text('0 stops  ·  Walked 0 times'), findsOneWidget);
      expect(find.text('No completed walks found.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      profile.dispose();
    });
  });
}
