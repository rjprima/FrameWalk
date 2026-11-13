import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/walk_history_service.dart';
import 'package:frame_walk/models/walk_photo_link.dart';
import 'package:frame_walk/models/walk_record.dart';

import 'fakes/fake_local_photo_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late WalkHistoryService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = WalkHistoryService(firestore: firestore);
    await firestore.collection('users').doc('user-1').set({
      'username': 'walker',
      'email': 'walker@example.com',
      'routesCompleted': 2,
      'photosTaken': 7,
    });
  });

  group('Saving completed walks', () {
    test('stores route, walk, stop, and prompt details', () async {
      final saved = await service.saveCompletedWalk(redSquareWalk(id: ''));

      expect(saved.id, isNotEmpty);
      final doc = await firestore
          .collection('users/user-1/walks')
          .doc(saved.id)
          .get();
      final data = doc.data()!;
      expect(data['userId'], 'user-1');
      expect(data['routeId'], '1');
      expect(data['stopIds'],
          ['red_stop_1', 'red_stop_2', 'red_stop_3', 'red_stop_4']);
      expect(data['promptIds'], contains('red_stop_1#0'));
      final firstStop = (data['stops'] as List).first as Map;
      expect(firstStop['latitude'], 47.6559);
      expect(firstStop['longitude'], -122.3078);

      final loaded = WalkRecord.fromMap(doc.id, data);
      expect(loaded.startedAt, walkStart);
      expect(loaded.completedAt, walkEnd);
      expect(loaded.stops.first.prompts.single.text,
          startsWith('Capture an interesting pattern'));
    });

    test('adds to the completed-route count without touching other stats',
        () async {
      await service.saveCompletedWalk(redSquareWalk(id: ''));

      final user = await firestore.collection('users').doc('user-1').get();
      expect(user['routesCompleted'], 3);
      expect(user['photosTaken'], 7);
      expect(user['username'], 'walker');
    });

    test('rejects a walk that ends before it starts', () {
      expect(
        () => WalkRecord(
          id: '',
          userId: 'user-1',
          routeId: '1',
          routeTitle: 'Red Square Walk',
          startedAt: walkEnd,
          completedAt: walkStart,
          stops: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Walk history', () {
    test('returns walks newest first and groups them by route', () async {
      final older = redSquareWalk(id: '');
      final newer = WalkRecord(
        id: '',
        userId: 'user-1',
        routeId: '1',
        routeTitle: 'Red Square Walk',
        startedAt: walkStart.add(const Duration(days: 2)),
        completedAt: walkEnd.add(const Duration(days: 2)),
        stops: older.stops,
      );
      final otherRoute = WalkRecord(
        id: '',
        userId: 'user-1',
        routeId: '2',
        routeTitle: 'UW Nature Walk',
        startedAt: walkStart.add(const Duration(days: 1)),
        completedAt: walkEnd.add(const Duration(days: 1)),
        stops: const [],
      );
      for (final walk in [older, otherRoute, newer]) {
        await service.saveCompletedWalk(walk);
      }

      final walks = await service.fetchWalks('user-1');
      expect(walks.map((w) => w.routeId), ['1', '2', '1']);

      final routes = WalkHistoryService.groupByRoute(walks);
      expect(routes.map((r) => r.routeTitle),
          ['Red Square Walk', 'UW Nature Walk']);
      expect(routes.first.walks, hasLength(2));
      expect(routes.first.lastWalkedAt, newer.completedAt);
    });

    test('returns no walks for a user who has none', () async {
      expect(await service.fetchWalks('user-1'), isEmpty);
    });
  });

  group('Photo links', () {
    WalkPhotoLink link({String? promptId}) => WalkPhotoLink(
          id: WalkPhotoLink.idFor(
            deviceInstallId: 'install-a',
            assetId: '1001',
          ),
          userId: 'user-1',
          walkId: 'walk-1',
          routeId: '1',
          assetId: '1001',
          platform: 'android',
          deviceInstallId: 'install-a',
          takenAt: walkStart,
          width: 4000,
          height: 3000,
          stopId: promptId == null ? null : 'red_stop_1',
          promptId: promptId,
        );

    test('stores a reference and metadata, never image data', () async {
      await service.savePhotoLink(link(promptId: 'red_stop_1#0'));

      final docs =
          await firestore.collection('users/user-1/walks/walk-1/photoLinks').get();
      final data = docs.docs.single.data();
      expect(data.keys, containsAll(['assetId', 'deviceInstallId', 'takenAt']));
      expect(
        data.keys.toSet().difference({
          'userId', 'walkId', 'routeId', 'assetId', 'platform',
          'deviceInstallId', 'takenAt', 'width', 'height', 'stopId',
          'promptId', 'status', 'updatedAt',
        }),
        isEmpty,
      );
      expect(data.values.whereType<List<int>>(), isEmpty);

      final loaded = await service.fetchPhotoLinks('user-1', 'walk-1');
      expect(loaded.single.promptId, 'red_stop_1#0');
      expect(loaded.single.takenAt, walkStart);
      expect(loaded.single.status, PhotoLinkStatus.linked);
    });

    test('saving the same photo again updates its link', () async {
      await service.savePhotoLink(link(promptId: 'red_stop_1#0'));
      await service.savePhotoLink(link());

      final loaded = await service.fetchPhotoLinks('user-1', 'walk-1');
      expect(loaded, hasLength(1));
      expect(loaded.single.promptId, isNull);
    });

    test('makes asset IDs safe to use as document IDs', () {
      final id = WalkPhotoLink.idFor(
        deviceInstallId: 'install-a',
        assetId: 'ABC-123/L0/001',
      );
      expect(id, 'install-a_ABC-123_L0_001');
    });
  });
}
