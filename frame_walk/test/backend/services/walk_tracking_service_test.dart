import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/location_source.dart';
import 'package:frame_walk/backend/services/route_progress_tracker.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/backend/services/walk_tracking_service.dart';
import 'package:frame_walk/models/route_stop.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/fake_location_source.dart';

// Simulates Firestore failing, or never hearing back from the server.
class ControllableWalkRepository extends WalkRepository {
  ControllableWalkRepository({required super.firestore});

  bool failCreate = false;
  bool failAppend = false;
  bool completeNeverFinishes = false;

  @override
  Future<void> createWalk(WalkedRoute walk) {
    if (failCreate) return Future.error(Exception('permission-denied'));
    return super.createWalk(walk);
  }

  @override
  Future<void> appendLocationPoints(WalkedRoute walk, points) {
    if (failAppend) return Future.error(Exception('unavailable'));
    return super.appendLocationPoints(walk, points);
  }

  @override
  Future<void> completeWalk(WalkedRoute walk) {
    if (completeNeverFinishes) {
      super.completeWalk(walk);
      return Completer<void>().future;
    }
    return super.completeWalk(walk);
  }
}

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
  // About 11 m of latitude.
  const step = 0.0001;

  late FakeFirebaseFirestore firestore;
  late ControllableWalkRepository repository;
  late FakeLocationSource location;
  late DateTime now;
  late WalkTrackingService service;

  WalkTrackingService buildService({
    Duration persistTimeout = const Duration(seconds: 8),
  }) {
    return WalkTrackingService(
      locationSource: location,
      repository: repository,
      clock: () => now,
      config: TrackingConfig(
        // Housekeeping is run by hand in tests.
        housekeepingInterval: const Duration(hours: 1),
        persistTimeout: persistTimeout,
      ),
    );
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = ControllableWalkRepository(firestore: firestore);
    location = FakeLocationSource();
    now = DateTime(2026, 11, 9, 10);
    await firestore.collection('users').doc(userId).set({
      'username': 'walker',
      'routesCompleted': 0,
    });
    service = buildService();
  });

  tearDown(() {
    service.dispose();
  });

  Future<LocationReadiness> start() => service.startWalk(
    userId: userId,
    routeId: '1',
    routeTitle: 'Red Square Walk',
    stops: stops,
  );

  // Emits a reading [seconds] after the previous one, moving the clock too.
  void walkTo(double lat, double lng, {int seconds = 10, double acc = 5}) {
    now = now.add(Duration(seconds: seconds));
    location.emit(sampleAt(lat, lng, now, accuracy: acc));
  }

  Future<List<Map<String, dynamic>>> savedPoints() async {
    final walkId = service.walk!.id;
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('walks')
        .doc(walkId)
        .collection('locationPoints')
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  Future<WalkedRoute?> savedWalk() =>
      repository.fetchWalk(userId, service.walk!.id);

  group('permissions', () {
    test('starts tracking when permission is already granted', () async {
      expect(await start(), LocationReadiness.ready);

      expect(service.phase, WalkPhase.active);
      expect(location.isStreaming, isTrue);
      expect(location.permissionRequests, 0);
      final walk = (await savedWalk())!;
      expect(walk.status, WalkStatus.active);
      expect(walk.startedAt, now);
      expect(walk.routeId, '1');
    });

    test('asks for permission and starts when the user allows it', () async {
      location.permission = LocationPermissionStatus.denied;
      location.answerToRequest = LocationPermissionStatus.granted;

      expect(await start(), LocationReadiness.ready);
      expect(location.permissionRequests, 1);
      expect(service.phase, WalkPhase.active);
    });

    test('records nothing when the user denies permission', () async {
      location.permission = LocationPermissionStatus.denied;
      location.answerToRequest = LocationPermissionStatus.denied;

      expect(await start(), LocationReadiness.denied);
      expect(service.phase, WalkPhase.blocked);
      expect(service.walk, isNull);
      expect(location.streamsOpened, 0);
      final walks = await firestore
          .collection('users')
          .doc(userId)
          .collection('walks')
          .get();
      expect(walks.docs, isEmpty);
    });

    test('does not ask again after "don\'t ask again"', () async {
      location.permission = LocationPermissionStatus.deniedForever;

      expect(await start(), LocationReadiness.deniedForever);
      expect(location.permissionRequests, 0);
      expect(service.phase, WalkPhase.blocked);
      await service.openAppSettings();
      expect(location.appSettingsOpened, 1);
    });

    test('blocks walks when only approximate location is allowed', () async {
      location.precise = false;
      expect(await start(), LocationReadiness.approximateOnly);
      expect(service.phase, WalkPhase.blocked);
      expect(location.streamsOpened, 0);
    });

    test('can start after the user fixes a denied permission', () async {
      location.permission = LocationPermissionStatus.denied;
      location.answerToRequest = LocationPermissionStatus.denied;
      await start();

      location.answerToRequest = LocationPermissionStatus.granted;
      expect(await start(), LocationReadiness.ready);
      expect(service.phase, WalkPhase.active);
    });
  });

  group('GPS disabled', () {
    test('blocks the walk without asking for permission', () async {
      location.serviceEnabled = false;
      location.permission = LocationPermissionStatus.denied;

      expect(await start(), LocationReadiness.serviceDisabled);
      expect(service.phase, WalkPhase.blocked);
      expect(location.permissionRequests, 0);
      await service.openLocationSettings();
      expect(location.locationSettingsOpened, 1);
    });

    test('pauses when GPS is turned off mid-walk and resumes after', () async {
      await start();

      location.setServiceEnabled(false);
      await pumpEventQueue();
      expect(service.signal, SignalStatus.gpsDisabled);
      expect(location.isStreaming, isFalse);
      expect(service.phase, WalkPhase.active, reason: 'the walk continues');

      location.setServiceEnabled(true);
      await pumpEventQueue();
      expect(location.isStreaming, isTrue);
      expect(service.signal, SignalStatus.acquiring);
    });

    test('handles a "service disabled" error from the stream', () async {
      await start();
      location.emitError(LocationErrorKind.serviceDisabled);
      expect(service.signal, SignalStatus.gpsDisabled);
      expect(location.isStreaming, isFalse);
    });

    test('handles permission revoked mid-walk and can recover', () async {
      await start();
      location.permission = LocationPermissionStatus.denied;
      location.emitError(LocationErrorKind.permissionDenied);
      expect(service.signal, SignalStatus.permissionRevoked);
      expect(location.isStreaming, isFalse);

      location.answerToRequest = LocationPermissionStatus.granted;
      await service.resumeTracking(requestPermission: true);
      expect(location.isStreaming, isTrue);
      expect(service.signal, SignalStatus.acquiring);
    });
  });

  group('location updates', () {
    test('records points with timestamps and adds up distance', () async {
      await start();
      final t1 = now.add(const Duration(seconds: 10));
      walkTo(47.6500, -122.3000);
      walkTo(47.6500 + step, -122.3000);
      walkTo(47.6500 + 2 * step, -122.3000);

      expect(service.signal, SignalStatus.good);
      expect(service.recordedPoints, hasLength(3));
      expect(service.recordedPoints.first.recordedAt, t1);
      expect(service.walk!.distanceMeters, closeTo(22.2, 0.5));
      expect(service.walk!.locationPointCount, 3);
      expect(service.walk!.lastLocationAt, now);
    });

    test('ignores readings that are too imprecise', () async {
      await start();
      walkTo(47.65, -122.30, acc: 120);

      expect(service.recordedPoints, isEmpty);
      expect(service.signal, SignalStatus.lowAccuracy);

      walkTo(47.65, -122.30, acc: 8);
      expect(service.recordedPoints, hasLength(1));
      expect(service.signal, SignalStatus.good);
    });

    test('records GPS jumps but does not count them as distance', () async {
      await start();
      walkTo(47.6500, -122.3000);
      // ~1.1 km in 10 s is not walking.
      walkTo(47.6600, -122.3000);

      expect(service.recordedPoints, hasLength(2));
      expect(service.walk!.distanceMeters, 0);
    });

    test('reports a lost signal when readings stop, and recovers', () async {
      await start();
      walkTo(47.65, -122.30);

      now = now.add(const Duration(minutes: 1));
      service.runHousekeeping();
      expect(service.signal, SignalStatus.good);

      now = now.add(const Duration(minutes: 2));
      service.runHousekeeping();
      expect(service.signal, SignalStatus.noRecentFix);
      expect(location.isStreaming, isTrue, reason: 'keeps listening');

      walkTo(47.65 + step, -122.30);
      expect(service.signal, SignalStatus.good);
    });

    test(
      'a stream error marks the signal lost without ending the walk',
      () async {
        await start();
        location.emitError(LocationErrorKind.other);
        expect(service.signal, SignalStatus.noRecentFix);
        expect(service.phase, WalkPhase.active);
        expect(location.isStreaming, isTrue);
      },
    );
  });

  group('route progress', () {
    test('detects approaching and reaching stops and saves them', () async {
      await start();
      final events = <StopEvent>[];
      final sub = service.stopEvents.listen(events.add);

      // 60 m north of Red Square, then at it.
      walkTo(47.6559 + 60 / 111195, -122.3078);
      walkTo(47.6559 + 5 / 111195, -122.3078, seconds: 60);
      await pumpEventQueue();

      expect(events.map((e) => e.type), [
        StopEventType.approaching,
        StopEventType.reached,
      ]);
      expect(events.last.stop.stopId, 'red_stop_1');
      expect(service.progress!.reachedCount, 1);
      expect(service.progress!.nextStop!.stopId, 'red_stop_2');

      // Reaching a stop is saved straight away, without waiting for a batch.
      final saved = (await savedWalk())!;
      expect(saved.reachedStopIds, ['red_stop_1']);
      expect(saved.stops.first.reachedAt, now);
      expect(await savedPoints(), hasLength(2));
      await sub.cancel();
    });
  });

  group('battery-conscious tracking', () {
    test(
      'asks for a 10 m distance filter and a 5 s minimum interval',
      () async {
        await start();
        expect(location.lastSettings!.distanceFilterMeters, 10);
        expect(
          location.lastSettings!.androidInterval,
          const Duration(seconds: 5),
        );
      },
    );

    test('saves points in batches of 10 rather than one by one', () async {
      await start();
      for (var i = 0; i < 9; i++) {
        walkTo(47.65 + i * step, -122.30);
      }
      await pumpEventQueue();
      expect(await savedPoints(), isEmpty);
      expect(service.pendingPointCount, 9);

      walkTo(47.65 + 9 * step, -122.30);
      await pumpEventQueue();
      expect(await savedPoints(), hasLength(10));
      expect(service.pendingPointCount, 0);
    });

    test('saves a partial batch after 30 seconds', () async {
      await start();
      walkTo(47.65, -122.30);
      walkTo(47.65 + step, -122.30);

      service.runHousekeeping();
      await pumpEventQueue();
      expect(await savedPoints(), isEmpty);

      now = now.add(const Duration(seconds: 30));
      service.runHousekeeping();
      await pumpEventQueue();
      expect(await savedPoints(), hasLength(2));
    });

    test('keeps points that failed to save and retries them', () async {
      await start();
      repository.failAppend = true;
      for (var i = 0; i < 10; i++) {
        walkTo(47.65 + i * step, -122.30);
      }
      await pumpEventQueue();
      expect(service.pendingPointCount, 10);
      expect(service.errorMessage, isNotNull);

      repository.failAppend = false;
      walkTo(47.65 + 10 * step, -122.30);
      await pumpEventQueue();
      expect(await savedPoints(), hasLength(11));
    });

    test(
      'stops listening in the background and resumes in the foreground',
      () async {
        await start();
        walkTo(47.65, -122.30);

        service.handleAppLifecycleState(AppLifecycleState.inactive);
        expect(
          location.isStreaming,
          isTrue,
          reason: 'brief interruptions such as dialogs do not pause',
        );

        service.handleAppLifecycleState(AppLifecycleState.paused);
        await pumpEventQueue();
        expect(location.isStreaming, isFalse);
        expect(service.signal, SignalStatus.pausedInBackground);
        expect(
          await savedPoints(),
          hasLength(1),
          reason: 'pending points are saved on the way out',
        );

        // No false "signal lost" while in the background.
        now = now.add(const Duration(minutes: 10));
        service.runHousekeeping();
        expect(service.signal, SignalStatus.pausedInBackground);

        service.handleAppLifecycleState(AppLifecycleState.resumed);
        await pumpEventQueue();
        expect(location.isStreaming, isTrue);
        expect(location.streamsOpened, 2);
        expect(service.signal, SignalStatus.acquiring);
      },
    );

    test(
      'reports GPS off when returning with location services disabled',
      () async {
        await start();
        service.handleAppLifecycleState(AppLifecycleState.hidden);
        location.serviceEnabled = false;
        service.handleAppLifecycleState(AppLifecycleState.resumed);
        await pumpEventQueue();
        expect(location.isStreaming, isFalse);
        expect(service.signal, SignalStatus.gpsDisabled);
      },
    );
  });

  group('completion and cancellation', () {
    test('completing stops tracking and saves the Walked-Route', () async {
      await start();
      final startedAt = now;
      walkTo(47.6559, -122.3078);
      walkTo(47.6559 + step, -122.3078);
      now = now.add(const Duration(minutes: 20));

      final walk = await service.completeWalk();

      expect(service.phase, WalkPhase.completed);
      expect(location.isStreaming, isFalse);
      expect(service.isListening, isFalse);
      expect(walk.completedAt, now);

      final saved = (await savedWalk())!;
      expect(saved.status, WalkStatus.completed);
      expect(saved.startedAt, startedAt);
      expect(saved.completedAt, now);
      expect(saved.reachedStopIds, ['red_stop_1']);
      expect(saved.locationPointCount, 2);
      expect(await savedPoints(), hasLength(2));
      final user = await firestore.collection('users').doc(userId).get();
      expect(user.data()!['routesCompleted'], 1);

      // Late readings are ignored, and the walk can't be completed twice.
      location.emit(sampleAt(47.0, -122.0, now));
      expect(service.recordedPoints, hasLength(2));
      expect(service.completeWalk, throwsStateError);
    });

    test('cancelling stops tracking and deletes the walk', () async {
      await start();
      for (var i = 0; i < 10; i++) {
        walkTo(47.65 + i * step, -122.30);
      }
      walkTo(47.65 + 10 * step, -122.30);
      await pumpEventQueue();
      final walkId = service.walk!.id;

      await service.cancelWalk();

      expect(service.phase, WalkPhase.cancelled);
      expect(location.isStreaming, isFalse);
      expect(await repository.fetchWalk(userId, walkId), isNull);
      expect(await repository.fetchLocationPoints(userId, walkId), isEmpty);
      final user = await firestore.collection('users').doc(userId).get();
      expect(user.data()!['routesCompleted'], 0);
    });

    test('disposing mid-walk stops the location stream', () async {
      final local = buildService();
      await local.startWalk(
        userId: userId,
        routeId: '1',
        routeTitle: 'Red Square Walk',
        stops: stops,
      );
      expect(location.isStreaming, isTrue);
      local.dispose();
      expect(location.isStreaming, isFalse);
    });

    test('finishes offline without waiting for the server', () async {
      service.dispose();
      service = buildService(persistTimeout: const Duration(milliseconds: 20));
      repository.completeNeverFinishes = true;
      await start();
      walkTo(47.65, -122.30);

      await service.completeWalk();
      expect(service.phase, WalkPhase.completed);
      expect(location.isStreaming, isFalse);
    });

    test('fails cleanly when the walk cannot be created', () async {
      repository.failCreate = true;
      await start();
      expect(service.phase, WalkPhase.failed);
      expect(service.errorMessage, isNotNull);
      expect(location.streamsOpened, 0);
    });

    test('rejects starting a second walk while one is active', () async {
      await start();
      expect(start, throwsStateError);
    });

    test('cannot complete or cancel when no walk is active', () {
      expect(service.completeWalk, throwsStateError);
      expect(service.cancelWalk, throwsStateError);
    });
  });
}
