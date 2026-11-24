import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/stop_notification_service.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/backend/services/walk_tracking_service.dart';
import 'package:frame_walk/models/route_stop.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/fake_location_source.dart';
import '../../fakes/fake_stop_notifications.dart';

void main() {
  group('notification text', () {
    const stop = WalkedStop(
      stopId: 'a',
      stopName: 'Red Square',
      latitude: 0,
      longitude: 0,
      prompt: 'Find a pattern',
    );

    test('matches the agreed wording', () {
      expect(stopReachedTitle, "You've reached your next stop!");
      expect(
        stopReachedBody(stop),
        'Red Square - Find a pattern. Open FrameWalk to see your progress.',
      );
    });

    test('does not double up punctuation the prompt already has', () {
      WalkedStop withPrompt(String prompt) => WalkedStop(
            stopId: 'a',
            stopName: 'Red Square',
            latitude: 0,
            longitude: 0,
            prompt: prompt,
          );
      expect(
        stopReachedBody(withPrompt('Find a pattern.')),
        startsWith('Red Square - Find a pattern. Open'),
      );
      expect(
        stopReachedBody(withPrompt('What do you see? ')),
        startsWith('Red Square - What do you see? Open'),
      );
      expect(
        stopReachedBody(withPrompt('')),
        'Red Square. Open FrameWalk to see your progress.',
      );
    });
  });

  group('notification payload', () {
    test('round-trips the walked route and stop IDs', () {
      const payload = StopNotificationPayload(
        walkedRouteId: 'walk-1',
        stopId: 'red_stop_1',
      );
      final encoded = payload.encode();
      expect(encoded, contains('"walkedRouteId":"walk-1"'));
      expect(encoded, contains('"stopId":"red_stop_1"'));
      expect(StopNotificationPayload.decode(encoded), payload);
    });

    test('ignores payloads FrameWalk did not write', () {
      for (final raw in [null, '', 'hello', '[]', '{"stopId":"a"}',
          '{"walkedRouteId":"","stopId":"a"}', '{"walkedRouteId":1}']) {
        expect(StopNotificationPayload.decode(raw), isNull, reason: '$raw');
      }
    });
  });

  group('notification IDs', () {
    test('are stable, positive, and differ per walk and stop', () {
      final id = stopNotificationId('walk-1', 'stop-1');
      expect(id, stopNotificationId('walk-1', 'stop-1'));
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThanOrEqualTo(0x7FFFFFFF));
      expect(id, isNot(stopNotificationId('walk-1', 'stop-2')));
      expect(id, isNot(stopNotificationId('walk-2', 'stop-1')));
    });
  });

  group('StopArrivalNotifier', () {
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

    late FakeLocationSource location;
    late FakeStopNotifications notifications;
    late WalkTrackingService service;
    late StopArrivalNotifier notifier;
    late DateTime now;

    setUp(() async {
      final firestore = FakeFirebaseFirestore();
      location = FakeLocationSource(supportsBackgroundTracking: true);
      notifications = FakeStopNotifications();
      now = DateTime(2026, 11, 24, 10);
      await firestore.collection('users').doc('user-1').set({
        'routesCompleted': 0,
      });
      service = WalkTrackingService(
        locationSource: location,
        repository: WalkRepository(firestore: firestore),
        clock: () => now,
        config: const TrackingConfig(housekeepingInterval: Duration(hours: 1)),
      );
      notifier = StopArrivalNotifier(
        walk: service,
        notifications: notifications,
      );
      await service.startWalk(
        userId: 'user-1',
        routeId: '1',
        routeTitle: 'Red Square Walk',
        stops: stops,
      );
    });

    tearDown(() async {
      await notifier.dispose();
      service.dispose();
    });

    void walkTo(double lat, double lng, {int seconds = 30}) {
      now = now.add(Duration(seconds: seconds));
      location.emit(sampleAt(lat, lng, now));
    }

    test('notifies with the stop and walk when reached off screen', () async {
      service.handleAppLifecycleState(AppLifecycleState.paused);
      walkTo(47.6559, -122.3078);
      await pumpEventQueue();

      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.stop.stopName, 'Red Square');
      expect(notifications.shown.single.stop.prompt, 'Find a pattern.');
      expect(notifications.shown.single.walkId, service.walk!.id);
    });

    test('does not notify about approaching a stop', () async {
      service.handleAppLifecycleState(AppLifecycleState.paused);
      walkTo(47.6559 + 60 / 111195, -122.3078);
      await pumpEventQueue();
      expect(notifications.shown, isEmpty);
    });

    test('leaves stops reached on screen to the SnackBar', () async {
      walkTo(47.6559, -122.3078);
      await pumpEventQueue();
      expect(notifications.shown, isEmpty);
    });

    test('notifies once per stop, for each stop in turn', () async {
      service.handleAppLifecycleState(AppLifecycleState.paused);
      walkTo(47.6559, -122.3078);
      walkTo(47.6559, -122.3078);
      await pumpEventQueue();
      walkTo(47.6553, -122.3099, seconds: 120);
      walkTo(47.6553, -122.3099);
      await pumpEventQueue();

      expect(
        notifications.shown.map((n) => n.stop.stopId),
        ['red_stop_1', 'red_stop_2'],
      );
    });

    test('stops notifying once the walk ends', () async {
      service.handleAppLifecycleState(AppLifecycleState.paused);
      await service.completeWalk();
      walkTo(47.6559, -122.3078);
      await pumpEventQueue();
      expect(notifications.shown, isEmpty);
    });
  });
}
