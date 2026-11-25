import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/stop_notification_service.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/backend/services/walk_tracking_service.dart';
import 'package:frame_walk/frontend/navigation/stop_notification_router.dart';
import 'package:frame_walk/frontend/screens/active_walk_page.dart';
import 'package:frame_walk/models/location_point.dart';
import 'package:frame_walk/models/mock_route_data.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/fake_location_source.dart';
import '../../fakes/fake_stop_notifications.dart';

// Holds fetchWalk open until [release], so the loading state can be seen.
class GatedWalkRepository extends WalkRepository {
  GatedWalkRepository({required super.firestore});

  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<WalkedRoute?> fetchWalk(String userId, String walkId) async {
    await _gate.future;
    return super.fetchWalk(userId, walkId);
  }
}

// The two ways a stop notification is tapped: while FrameWalk is still
// running (in the background), and after it was closed, when the tap
// launches it. In both, only the IDs in the payload are carried over.
void main() {
  const userId = 'user-1';
  final route = MockRouteData.routes.firstWhere((r) => r.id == '1');
  final stops = MockRouteData.getStops('1');
  final firstStop = stops.first;

  late FakeFirebaseFirestore firestore;
  late WalkRepository repository;
  late FakeLocationSource location;
  late FakeStopNotifications notifications;
  late List<WalkTrackingService> services;
  late GlobalKey<NavigatorState> navigatorKey;
  late Completer<String> authRestored;
  late StopNotificationRouter router;

  WalkTrackingService newService() {
    final service = WalkTrackingService(
      locationSource: location,
      repository: repository,
    );
    services.add(service);
    return service;
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = WalkRepository(firestore: firestore);
    location = FakeLocationSource(supportsBackgroundTracking: true);
    notifications = FakeStopNotifications();
    services = [];
    navigatorKey = GlobalKey<NavigatorState>();
    await firestore.collection('users').doc(userId).set({
      'routesCompleted': 0,
    });
  });

  // Called at the start of each test rather than in setUp: futures made in
  // setUp belong to the real event loop, which tester.pump doesn't run, so
  // the router would never see sign-in complete.
  void createRouter() {
    authRestored = Completer<String>();
    router = StopNotificationRouter(
      navigatorKey: navigatorKey,
      signedInUserId: () => authRestored.future,
      buildWalkPage: (payload, uid) => ActiveWalkPage.resume(
        resumeWalkId: payload.walkedRouteId,
        focusStopId: payload.stopId,
        trackingService: newService(),
        stopNotifications: notifications,
        userId: uid,
        showMap: false,
      ),
    );
  }

  tearDown(() {
    for (final service in services) {
      service.dispose();
    }
  });

  String tapPayload(String walkId) =>
      StopNotificationPayload(walkedRouteId: walkId, stopId: firstStop.id)
          .encode();

  // A tap takes a few frames to arrive: sign-in, the push, the first build.
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 10 && finder.evaluate().isEmpty; i++) {
      await tester.pump();
    }
  }

  Future<void> showApp(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      );

  Future<void> endWalks(WidgetTester tester) async {
    for (final service in services) {
      if (service.phase == WalkPhase.active) {
        await tester.runAsync(service.cancelWalk);
      }
    }
    await tester.pumpAndSettle();
  }

  group('app still running in the background', () {
    testWidgets('shows the stop on the open walk screen, not a second one', (
      tester,
    ) async {
      createRouter();
      authRestored.complete(userId);
      await showApp(tester);
      final service = newService();
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ActiveWalkPage(
            route: route,
            stops: stops,
            routePoints: const [],
            trackingService: service,
            stopNotifications: notifications,
            userId: userId,
            showMap: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lock the phone and reach the first two stops.
      final start = DateTime.now();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      location.emit(sampleAt(firstStop.latitude, firstStop.longitude, start));
      await tester.pump();
      location.emit(
        sampleAt(
          stops[1].latitude,
          stops[1].longitude,
          start.add(const Duration(minutes: 5)),
        ),
      );
      await tester.pump();
      expect(notifications.shown, hasLength(2));
      final walkId = service.walk!.id;

      // Tapping brings FrameWalk back, then the tap is delivered.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // The tap is for the first stop's notification, not the latest one.
      router.handleTap(tapPayload(walkId));
      await tester.pumpAndSettle();

      expect(find.byType(ActiveWalkPage), findsOneWidget);
      expect(services, hasLength(1), reason: 'no second tracking service');
      expect(location.streamsOpened, 1, reason: 'tracking was not restarted');
      expect(
        find.text('${firstStop.name}: ${firstStop.prompt}'),
        findsOneWidget,
        reason: "the Current prompt box shows the tapped notification's stop",
      );
      expect(find.text('2 of 4 stops reached'), findsOneWidget);

      // Reaching the next stop moves the box on to it.
      location.emit(
        sampleAt(
          stops[2].latitude,
          stops[2].longitude,
          start.add(const Duration(minutes: 10)),
        ),
      );
      await tester.pump();
      expect(find.text('3 of 4 stops reached'), findsOneWidget);
      expect(find.text('${stops[2].name}: ${stops[2].prompt}'), findsOneWidget);
      expect(find.text('${firstStop.name}: ${firstStop.prompt}'), findsNothing);

      await endWalks(tester);
    });
  });

  group('app launched from closed by the tap', () {
    // A walk FrameWalk was tracking before it was closed: the first stop is
    // reached and two points are saved. Nothing about it is in memory.
    Future<String> savedWalk(WidgetTester tester) async {
      late String walkId;
      await tester.runAsync(() async {
        final started = WalkedRoute.start(
          id: repository.newWalkId(userId),
          userId: userId,
          routeId: route.id,
          routeTitle: route.name,
          stops: stops,
          startedAt: DateTime(2026, 11, 24, 10),
          trackingMode: backgroundTrackingMode,
        );
        await repository.createWalk(started);
        final walk = started
            .withStopReached(firstStop.id, DateTime(2026, 11, 24, 10, 5))
            .copyWith(locationPointCount: 2);
        await repository.appendLocationPoints(walk, [
          for (var i = 0; i < 2; i++)
            LocationPoint.fromSample(
              i,
              sampleAt(
                firstStop.latitude,
                firstStop.longitude,
                DateTime(2026, 11, 24, 10, 4 + i),
              ),
            ),
        ]);
        walkId = walk.id;
      });
      return walkId;
    }

    testWidgets('waits for sign-in, then reopens the saved walk', (
      tester,
    ) async {
      final gated = GatedWalkRepository(firestore: firestore);
      repository = gated;
      createRouter();
      final walkId = await savedWalk(tester);

      // As in main(): the app starts, then the launch tap is handed over
      // while Firebase is still restoring the signed-in user.
      await showApp(tester);
      router.handleTap(tapPayload(walkId));
      await tester.pump();
      expect(find.byType(ActiveWalkPage), findsNothing);

      authRestored.complete(userId);
      await pumpUntilFound(tester, find.byType(ActiveWalkPage));
      expect(find.byType(ActiveWalkPage), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'a loading state shows while the walk is fetched',
      );

      // Loading from storage, then tracking again.
      gated.release();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      final service = services.single;
      expect(service.phase, WalkPhase.active);
      expect(service.walk!.id, walkId);
      expect(location.isStreaming, isTrue);
      expect(find.text('Red Square Walk'), findsOneWidget);
      expect(find.text('1 of 4 stops reached'), findsOneWidget);
      expect(
        find.text('${firstStop.name}: ${firstStop.prompt}'),
        findsOneWidget,
      );
      expect(service.recordedPoints, hasLength(2));

      await endWalks(tester);
    });

    testWidgets('opens one walk screen however many times it is tapped', (
      tester,
    ) async {
      createRouter();
      final walkId = await savedWalk(tester);
      await showApp(tester);

      // iOS can report a launch tap twice, and users tap again while waiting.
      router.handleTap(tapPayload(walkId));
      router.handleTap(tapPayload(walkId));
      authRestored.complete(userId);
      await tester.pump();
      await tester.pump();
      router.handleTap(tapPayload(walkId));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();

      expect(find.byType(ActiveWalkPage), findsOneWidget);
      expect(services, hasLength(1));
      expect(location.streamsOpened, 1);

      await endWalks(tester);
    });

    testWidgets('explains when the tapped walk has already finished', (
      tester,
    ) async {
      createRouter();
      final walkId = await savedWalk(tester);
      await tester.runAsync(() async {
        final walk = (await repository.fetchWalk(userId, walkId))!;
        await repository.completeWalk(walk.copyWith(
          status: WalkStatus.completed,
          completedAt: DateTime(2026, 11, 24, 11),
        ));
      });
      authRestored.complete(userId);
      await showApp(tester);

      router.handleTap(tapPayload(walkId));
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();

      expect(find.textContaining('already finished'), findsOneWidget);
      expect(location.isStreaming, isFalse);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('ignores taps on notifications FrameWalk did not create', (
      tester,
    ) async {
      createRouter();
      authRestored.complete(userId);
      await showApp(tester);
      await router.handleTap('not a FrameWalk payload');
      await router.handleTap(null);
      await tester.pumpAndSettle();
      expect(find.byType(ActiveWalkPage), findsNothing);
    });
  });
}
