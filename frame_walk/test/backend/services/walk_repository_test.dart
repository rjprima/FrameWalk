import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/models/location_point.dart';
import 'package:frame_walk/models/route_stop.dart';
import 'package:frame_walk/models/walked_route.dart';

void main() {
  const userId = 'user-1';
  const stops = [
    RouteStop(
      id: 'red_stop_1',
      name: 'Red Square',
      prompt: 'Find a pattern.',
      latitude: 47.6559,
      longitude: -122.3078,
    ),
    RouteStop(
      id: 'red_stop_2',
      name: 'Suzzallo Library',
      prompt: 'Light and shadow.',
      latitude: 47.6553,
      longitude: -122.3099,
    ),
  ];
  final startedAt = DateTime(2026, 11, 9, 10);

  late FakeFirebaseFirestore firestore;
  late WalkRepository repository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = WalkRepository(firestore: firestore);
    await firestore.collection('users').doc(userId).set({
      'username': 'walker',
      'routesCompleted': 0,
    });
  });

  WalkedRoute newWalk() => WalkedRoute.start(
    id: repository.newWalkId(userId),
    userId: userId,
    routeId: '1',
    routeTitle: 'Red Square Walk',
    stops: stops,
    startedAt: startedAt,
  );

  DocumentReference<Map<String, dynamic>> walkDoc(String id) =>
      firestore.collection('users').doc(userId).collection('walks').doc(id);

  LocationPoint point(int i) => LocationPoint.fromSample(
    i,
    LocationSample(
      latitude: 47.6559 + i * 0.0001,
      longitude: -122.3078,
      accuracyMeters: 5,
      recordedAt: startedAt.add(Duration(seconds: 10 * i)),
    ),
  );

  test('generates a unique walk ID for each walk', () {
    expect(repository.newWalkId(userId), isNot(repository.newWalkId(userId)));
  });

  test('stores an active walk with the route, stops, and start time', () async {
    final walk = newWalk();
    await repository.createWalk(walk);

    final data = (await walkDoc(walk.id).get()).data()!;
    expect(data['status'], 'active');
    expect(data['routeId'], '1');
    expect(data['userId'], userId);
    expect(data['trackingMode'], 'foreground');
    expect((data['startedAt'] as Timestamp).toDate(), startedAt);
    expect(data.containsKey('completedAt'), isFalse);
    expect(data['stopIds'], ['red_stop_1', 'red_stop_2']);
    // Same stop shape the photo-gallery branch reads.
    final firstStop = (data['stops'] as List).first as Map;
    expect(firstStop['stopId'], 'red_stop_1');
    expect(firstStop['latitude'], 47.6559);
    expect(firstStop['longitude'], -122.3078);
    expect(firstStop['prompts'], [
      {'id': 'red_stop_1#0', 'text': 'Find a pattern.'},
    ]);
  });

  test('only creates walks that are active', () async {
    final completed = newWalk().copyWith(
      status: WalkStatus.completed,
      completedAt: startedAt.add(const Duration(minutes: 1)),
    );
    expect(() => repository.createWalk(completed), throwsArgumentError);
  });

  test(
    'saves location points with timestamps, in order, without duplicates',
    () async {
      final walk = newWalk();
      await repository.createWalk(walk);

      final points = [point(0), point(1), point(2)];
      final updated = walk.copyWith(
        distanceMeters: 22,
        locationPointCount: 3,
        lastLocationAt: points.last.recordedAt,
      );
      await repository.appendLocationPoints(updated, points);
      // A retry of the same points must not create copies.
      await repository.appendLocationPoints(updated, points.sublist(1));

      final saved = await repository.fetchLocationPoints(userId, walk.id);
      expect(saved.map((p) => p.sequence), [0, 1, 2]);
      expect(saved[2].recordedAt, startedAt.add(const Duration(seconds: 20)));
      expect(saved[1].latitude, closeTo(47.656, 1e-9));

      final data = (await walkDoc(walk.id).get()).data()!;
      expect(data['distanceMeters'], 22);
      expect(data['locationPointCount'], 3);
    },
  );

  test('saves which stops were reached and when', () async {
    final walk = newWalk();
    await repository.createWalk(walk);
    final reachedAt = startedAt.add(const Duration(minutes: 4));

    await repository.updateProgress(
      walk.withStopReached('red_stop_1', reachedAt),
    );

    final saved = (await repository.fetchWalk(userId, walk.id))!;
    expect(saved.reachedStopIds, ['red_stop_1']);
    expect(saved.stops.first.reachedAt, reachedAt);
    expect(saved.stops.last.reachedAt, isNull);
  });

  test('completes a walk and counts it in the user statistics', () async {
    final walk = newWalk();
    await repository.createWalk(walk);
    final completedAt = startedAt.add(const Duration(minutes: 30));

    await repository.completeWalk(
      walk.copyWith(
        status: WalkStatus.completed,
        completedAt: completedAt,
        distanceMeters: 1200,
      ),
    );

    final saved = (await repository.fetchWalk(userId, walk.id))!;
    expect(saved.status, WalkStatus.completed);
    expect(saved.completedAt, completedAt);
    expect(saved.duration, const Duration(minutes: 30));
    expect(saved.distanceMeters, 1200);
    final user = await firestore.collection('users').doc(userId).get();
    expect(user.data()!['routesCompleted'], 1);
  });

  test('lists only completed walks, newest first', () async {
    final older = newWalk();
    final newer = newWalk();
    final active = newWalk();
    for (final walk in [older, newer, active]) {
      await repository.createWalk(walk);
    }
    await repository.completeWalk(
      older.copyWith(
        status: WalkStatus.completed,
        completedAt: startedAt.add(const Duration(minutes: 10)),
      ),
    );
    await repository.completeWalk(
      newer.copyWith(
        status: WalkStatus.completed,
        completedAt: startedAt.add(const Duration(minutes: 20)),
      ),
    );

    final walks = await repository.fetchCompletedWalks(userId);
    expect(walks.map((w) => w.id), [newer.id, older.id]);
  });

  test('deleting a cancelled walk removes its location history', () async {
    final walk = newWalk();
    await repository.createWalk(walk);
    await repository.appendLocationPoints(walk, [point(0), point(1)]);

    await repository.deleteWalk(walk);

    expect((await walkDoc(walk.id).get()).exists, isFalse);
    expect(await repository.fetchLocationPoints(userId, walk.id), isEmpty);
    final user = await firestore.collection('users').doc(userId).get();
    expect(user.data()!['routesCompleted'], 0);
  });

  group('WalkedRoute', () {
    test('round-trips through a Firestore map', () {
      final walk = newWalk()
          .withStopReached(
            'red_stop_2',
            startedAt.add(const Duration(minutes: 3)),
          )
          .copyWith(
            status: WalkStatus.completed,
            completedAt: startedAt.add(const Duration(minutes: 9)),
            distanceMeters: 640.5,
            locationPointCount: 42,
          );
      final copy = WalkedRoute.fromMap(walk.id, walk.toMap());
      expect(copy.toMap(), walk.toMap());
    });

    test('rejects a walk that ends before it starts', () {
      expect(
        () => newWalk().copyWith(
          status: WalkStatus.completed,
          completedAt: startedAt.subtract(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a completed walk with no completion time', () {
      expect(
        () => newWalk().copyWith(status: WalkStatus.completed),
        throwsArgumentError,
      );
    });
  });
}
