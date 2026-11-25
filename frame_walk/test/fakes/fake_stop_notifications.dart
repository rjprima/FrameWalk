import 'package:frame_walk/backend/services/stop_notification_service.dart';
import 'package:frame_walk/models/walked_route.dart';

// Records what would have been shown instead of showing it.
class FakeStopNotifications implements StopNotificationService {
  bool allow;
  int permissionRequests = 0;
  final List<({String walkId, WalkedStop stop})> shown = [];

  FakeStopNotifications({this.allow = true});

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<void> showStopReached({
    required String walkId,
    required WalkedStop stop,
  }) async {
    shown.add((walkId: walkId, stop: stop));
  }
}
