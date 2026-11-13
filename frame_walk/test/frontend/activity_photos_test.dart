import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/providers/route_provider.dart';
import 'package:frame_walk/backend/services/local_photo_service.dart';
import 'package:frame_walk/backend/services/walk_gallery_service.dart';
import 'package:frame_walk/backend/services/walk_history_service.dart';
import 'package:frame_walk/backend/test/fakes/fake_local_photo_service.dart';
import 'package:frame_walk/frontend/screens/activity_page.dart';
import 'package:frame_walk/frontend/screens/walk_photos_page.dart';
import 'package:frame_walk/frontend/widgets/local_photo_thumbnail.dart';
import 'package:frame_walk/frontend/widgets/photo_access_card.dart';
import 'package:frame_walk/models/walk_record.dart';
import 'package:provider/provider.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late WalkHistoryService history;
  late FakeLocalPhotoService photos;
  late WalkGalleryService galleryService;
  late RouteProvider routes;

  DateTime minutesIn(int minutes) => walkStart.add(Duration(minutes: minutes));

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    history = WalkHistoryService(firestore: firestore);
    photos = FakeLocalPhotoService();
    galleryService = WalkGalleryService(photos: photos, history: history);
    routes = RouteProvider();
    await firestore.collection('users').doc('user-1').set({
      'username': 'walker',
      'routesCompleted': 0,
    });
  });

  Future<WalkRecord> saveWalk() => history.saveCompletedWalk(redSquareWalk());

  Future<void> openActivity(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: routes,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityPage(
              walkHistoryService: history,
              photoService: photos,
              userId: 'user-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openWalkPhotos(WidgetTester tester, WalkRecord walk) async {
    // Tall enough that every section is on screen without scrolling.
    tester.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: WalkPhotosPage(walk: walk, galleryService: galleryService),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Activity page', () {
    testWidgets('lists completed routes and opens a walk\'s photos',
        (tester) async {
      await saveWalk();
      photos.gallery.addAll([
        photoAt('at-red-square', minutesIn(3), location: redSquare),
        photoAt('at-suzzallo', minutesIn(12), location: suzzallo),
      ]);

      await openActivity(tester);
      expect(find.text('Red Square Walk'), findsOneWidget);
      expect(find.textContaining('Walked once'), findsOneWidget);

      await tester.tap(find.text('Red Square Walk'));
      await tester.pumpAndSettle();
      expect(find.text('Nov 1, 2026'), findsOneWidget);
      expect(find.textContaining('10:00 AM – 10:40 AM'), findsOneWidget);

      await tester.tap(find.text('Nov 1, 2026'));
      await tester.pumpAndSettle();
      expect(find.byType(WalkPhotosPage), findsOneWidget);
      expect(find.text('Stop 1 · Red Square'), findsOneWidget);
      expect(find.byType(LocalPhotoThumbnail), findsNWidgets(2));
    });

    testWidgets('shows a message when there are no previous walks',
        (tester) async {
      await openActivity(tester);

      expect(find.textContaining('No previous walks yet'), findsOneWidget);
      expect(photos.checkAccessCalls, 0,
          reason: 'the walk list never touches the gallery');
    });

    testWidgets('saved walks tab still works', (tester) async {
      routes
        ..toggleBookmark('2')
        ..toggleBookmark('3');
      await openActivity(tester);

      await tester.tap(find.text('Saved Walks').first);
      await tester.pumpAndSettle();

      expect(find.text('UW Nature Walk'), findsOneWidget);
      expect(find.text('Waterfront Views'), findsOneWidget);
    });
  });

  group('Walk photos permissions', () {
    testWidgets('explains photo access and asks only when the user taps',
        (tester) async {
      photos
        ..access = GalleryAccess.denied
        ..accessAfterRequest = GalleryAccess.full
        ..gallery.add(photoAt('a', minutesIn(3), location: redSquare));
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);
      expect(find.byType(PhotoAccessCard), findsOneWidget);
      expect(find.textContaining('Your photos stay on this phone'),
          findsOneWidget);
      expect(photos.requestAccessCalls, 0);

      await tester.tap(find.text('Allow photo access'));
      await tester.pumpAndSettle();

      expect(photos.requestAccessCalls, 1);
      expect(find.byType(PhotoAccessCard), findsNothing);
      expect(find.byType(LocalPhotoThumbnail), findsOneWidget);
    });

    testWidgets('offers Settings after the user says no', (tester) async {
      photos
        ..access = GalleryAccess.denied
        ..accessAfterRequest = GalleryAccess.denied;
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);
      expect(find.text('Open Settings'), findsNothing);

      await tester.tap(find.text('Allow photo access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Settings'));

      expect(photos.openSettingsCalls, 1);
    });

    testWidgets('refreshes when access is granted in Settings',
        (tester) async {
      photos
        ..access = GalleryAccess.denied
        ..gallery.add(photoAt('a', minutesIn(3), location: redSquare));
      final walk = await saveWalk();
      await openWalkPhotos(tester, walk);

      photos.access = GalleryAccess.full;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoAccessCard), findsNothing);
      expect(find.byType(LocalPhotoThumbnail), findsOneWidget);
    });

    testWidgets('limited access shows a banner to change the selection',
        (tester) async {
      photos.access = GalleryAccess.limited;
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);
      await tester.tap(find.text('Change selection'));
      await tester.pumpAndSettle();

      expect(photos.manageSelectionCalls, 1);
    });
  });

  group('Walk photos empty states', () {
    testWidgets('no photos in the time window', (tester) async {
      photos.gallery.add(photoAt('old', DateTime(2025, 1, 1)));
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);

      expect(find.text('No photos associated with this walk'), findsOneWidget);
      expect(find.textContaining("match this walk's time window"),
          findsOneWidget);
      expect(find.text('Add photos from camera roll'), findsOneWidget);
    });

    testWidgets('a previously added photo was deleted', (tester) async {
      final photo = photoAt('a', minutesIn(3));
      photos.gallery.add(photo);
      final walk = await saveWalk();
      await galleryService.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');
      photos.deletePhotoOutsideApp('a');

      await openWalkPhotos(tester, walk);
      expect(find.textContaining('no longer exist on this device'),
          findsOneWidget);

      await tester.tap(find.text('Remove from walk'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer exist'), findsNothing);
    });
  });

  group('Associating photos', () {
    testWidgets('assigns a suggested photo to a prompt', (tester) async {
      photos.gallery.add(photoAt('no-gps', minutesIn(20)));
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);
      expect(find.text('Possibly from this walk'), findsOneWidget);

      await tester.tap(find.byType(LocalPhotoThumbnail));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suzzallo Library'));
      await tester.pumpAndSettle();

      expect(find.text('Possibly from this walk'), findsNothing);
      final links = await history.fetchPhotoLinks('user-1', walk.id);
      expect(links.single.promptId, 'red_stop_2#0');
    });

    testWidgets('removes a photo without deleting it from the camera roll',
        (tester) async {
      final photo = photoAt('a', minutesIn(3), location: redSquare);
      photos.gallery.add(photo);
      final walk = await saveWalk();
      await galleryService.assignPhotos(walk, [photo], promptId: 'red_stop_1#0');

      await openWalkPhotos(tester, walk);
      await tester.tap(find.byType(LocalPhotoThumbnail));
      await tester.pumpAndSettle();
      expect(find.text('The photo stays in your camera roll.'), findsOneWidget);
      await tester.tap(find.text('Remove from this walk'));
      await tester.pumpAndSettle();

      expect(find.byType(LocalPhotoThumbnail), findsNothing);
      expect(photos.gallery, contains(photo));
    });

    testWidgets('adds several photos from the camera roll to one prompt',
        (tester) async {
      photos.gallery.addAll([
        photoAt('old-1', DateTime(2025, 5, 1)),
        photoAt('old-2', DateTime(2025, 5, 2)),
      ]);
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);
      await tester.tap(find.text('Add photos from camera roll'));
      await tester.pumpAndSettle();
      final thumbnails = find.byType(LocalPhotoThumbnail);
      expect(thumbnails, findsNWidgets(2));
      await tester.tap(thumbnails.at(0));
      await tester.tap(thumbnails.at(1));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drumheller Fountain'));
      await tester.pumpAndSettle();

      expect(find.byType(LocalPhotoThumbnail), findsNWidgets(2));
      final links = await history.fetchPhotoLinks('user-1', walk.id);
      expect(links.map((l) => l.promptId), everyElement('red_stop_3#0'));
    });

    testWidgets('shows an icon when a thumbnail cannot be read',
        (tester) async {
      photos.gallery.add(photoAt('heic', minutesIn(3), location: redSquare));
      photos.unreadableThumbnails.add('heic');
      final walk = await saveWalk();

      await openWalkPhotos(tester, walk);

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
