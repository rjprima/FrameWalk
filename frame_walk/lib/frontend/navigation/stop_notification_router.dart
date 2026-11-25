import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/services/stop_notification_service.dart';
import '../screens/active_walk_page.dart';

typedef WalkPageBuilder = Widget Function(
  StopNotificationPayload payload,
  String userId,
);

// Opens the walk screen when a stop notification is tapped, whether
// FrameWalk was on screen, in the background, or closed (see main.dart for
// where taps come from).
//
// Uses the app's ordinary Navigator.push, through the root navigator's key,
// because a tap arrives from outside the widget tree.
class StopNotificationRouter {
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<String> Function() _waitForUserId;
  final WalkPageBuilder _buildWalkPage;

  // Taps are handled one at a time, so two quick taps (or iOS reporting a
  // launch tap twice) can't both push a walk screen.
  Future<void> _queue = Future.value();

  StopNotificationRouter({
    required this.navigatorKey,
    required Future<String> Function() signedInUserId,
    WalkPageBuilder? buildWalkPage,
  })  : _waitForUserId = signedInUserId,
        _buildWalkPage = buildWalkPage ?? _defaultWalkPage;

  static Widget _defaultWalkPage(StopNotificationPayload payload, String uid) =>
      ActiveWalkPage.resume(
        resumeWalkId: payload.walkedRouteId,
        focusStopId: payload.stopId,
        userId: uid,
      );

  // [rawPayload] is a notification's payload string. Anything that isn't a
  // FrameWalk stop payload is ignored.
  Future<void> handleTap(String? rawPayload) {
    final payload = StopNotificationPayload.decode(rawPayload);
    if (payload == null) return Future.value();
    return _queue = _queue.then((_) => _open(payload)).catchError(
      (Object error) {
        debugPrint('FrameWalk: could not open tapped notification: $error');
      },
    );
  }

  Future<void> _open(StopNotificationPayload payload) async {
    // After a cold launch Firebase restores the signed-in user
    // asynchronously; until then the walk can't be found (it's stored under
    // the user). Waits through sign-in if the user was signed out.
    final userId = await _waitForUserId();
    final navigator = await _waitForNavigator();

    // Only one walk is tracked at a time. If its screen is open, show the
    // stop there instead of opening a second screen (which would also start
    // a second location stream).
    final open = ActiveWalkPage.openScreen;
    if (open != null) {
      if (open.walkId == payload.walkedRouteId) open.showStop(payload.stopId);
      return;
    }

    // The screen shows its own loading state while it fetches the walk.
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => _buildWalkPage(payload, userId),
      ),
    );
    // Lets the new screen build and register itself as the open screen
    // before the next tap is handled.
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<NavigatorState> _waitForNavigator() async {
    while (navigatorKey.currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    return navigatorKey.currentState!;
  }
}
