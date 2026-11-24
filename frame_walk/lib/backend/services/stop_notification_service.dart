import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/walked_route.dart';
import 'route_progress_tracker.dart';
import 'walk_tracking_service.dart';

// Everything FrameWalk needs to tell the user they reached a stop while the
// app is off screen. The rest of the app depends on this rather than on
// flutter_local_notifications, so it can be faked in tests.
//
// These are local notifications: the phone already knows where the user is
// and where the stops are, so no server (or Firebase Cloud Messaging) is
// involved.
abstract class StopNotificationService {
  // Asks the user to allow notifications, if the OS still allows asking.
  // Returns whether they're allowed. Never throws.
  Future<bool> requestPermission();

  // Never throws: a notification failing must not interrupt the walk.
  Future<void> showStopReached({
    required String walkId,
    required WalkedStop stop,
  });
}

const String stopReachedTitle = "You've reached your next stop!";

// "Red Square - Find a pattern. Open FrameWalk to see your progress."
String stopReachedBody(WalkedStop stop) {
  final prompt = stop.prompt.trim();
  final String lead;
  if (prompt.isEmpty) {
    lead = '${stop.stopName}.';
  } else if (RegExp(r'[.!?]$').hasMatch(prompt)) {
    lead = '${stop.stopName} - $prompt';
  } else {
    lead = '${stop.stopName} - $prompt.';
  }
  return '$lead Open FrameWalk to see your progress.';
}

// The same walk and stop always get the same ID, so if a notification were
// ever shown twice the OS would replace the first rather than add a second.
// String.hashCode isn't guaranteed stable between runs, so this uses 32-bit
// FNV-1a, masked to a positive int as Android requires.
int stopNotificationId(String walkId, String stopId) {
  var hash = 0x811c9dc5;
  for (final unit in '$walkId/$stopId'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

// Shows a notification for each stop reached while FrameWalk is off screen.
// On screen, the walk page's SnackBar already says the same thing, so a
// notification banner on top would be a duplicate.
//
// Duplicates are prevented three ways: RouteProgressTracker reports each
// stop reached only once; this class remembers which stops it has notified
// about; and each stop's notification ID is fixed (see stopNotificationId).
class StopArrivalNotifier {
  final WalkTrackingService _tracking;
  final StopNotificationService _notifier;
  final bool notifyInForeground;
  final Set<String> _notified = {};
  late final StreamSubscription<StopEvent> _subscription;

  StopArrivalNotifier({
    required WalkTrackingService walk,
    required StopNotificationService notifications,
    this.notifyInForeground = false,
  })  : _tracking = walk,
        _notifier = notifications {
    _subscription = _tracking.stopEvents.listen(_onStopEvent);
  }

  void _onStopEvent(StopEvent event) {
    if (event.type != StopEventType.reached) return;
    final walkId = _tracking.walk?.id;
    if (walkId == null) return;
    if (!_notified.add('$walkId/${event.stop.stopId}')) return;
    if (!_tracking.isInBackground && !notifyInForeground) return;
    _notifier.showStopReached(walkId: walkId, stop: event.stop);
  }

  Future<void> dispose() => _subscription.cancel();
}

// StopNotificationService using the flutter_local_notifications plugin.
class LocalStopNotificationService implements StopNotificationService {
  // Android groups notifications into channels the user can control in
  // Settings. Sound and importance are fixed when a channel is first
  // created, so changing them later needs a new channel ID.
  static const _channelId = 'stop_arrivals';
  static const _channelName = 'Photo stops';
  static const _channelDescription =
      'Tells you when you reach a stop on your walk.';

  // White-on-transparent icon for the status bar
  // (android/app/src/main/res/drawable).
  static const _androidIcon = 'ic_stat_framewalk';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _initialized;

  LocalStopNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  // Set up on first use rather than at launch. The permission flags are off
  // so iOS doesn't prompt the moment FrameWalk opens; requestPermission asks
  // when a walk starts, when the reason is obvious.
  Future<bool> _ensureInitialized() {
    return _initialized ??= () async {
      try {
        return await _plugin.initialize(
              settings: const InitializationSettings(
                android: AndroidInitializationSettings(_androidIcon),
                iOS: DarwinInitializationSettings(
                  requestAlertPermission: false,
                  requestBadgePermission: false,
                  requestSoundPermission: false,
                ),
              ),
            ) ??
            false;
      } catch (error) {
        debugPrint('FrameWalk: notifications unavailable: $error');
        _initialized = null;
        return false;
      }
    }();
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _ensureInitialized()) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android 13+ shows a prompt; earlier versions allow by default.
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      }
    } catch (error) {
      debugPrint('FrameWalk: notification permission failed: $error');
    }
    return false;
  }

  @override
  Future<void> showStopReached({
    required String walkId,
    required WalkedStop stop,
  }) async {
    if (!await _ensureInitialized()) return;
    final body = stopReachedBody(stop);
    try {
      await _plugin.show(
        id: stopNotificationId(walkId, stop.stopId),
        title: stopReachedTitle,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            // High importance shows a heads-up banner, not just a tray icon.
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.navigation,
            // Long prompts would otherwise be cut to one line.
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(presentSound: true),
        ),
      );
    } catch (error) {
      debugPrint('FrameWalk: could not show stop notification: $error');
    }
  }
}
