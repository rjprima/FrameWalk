import 'dart:async';

import 'package:frame_walk/backend/services/location_source.dart';
import 'package:frame_walk/models/location_point.dart';

// A LocationSource driven by the test: set permission and service state, then
// push readings with [emit].
class FakeLocationSource implements LocationSource {
  bool serviceEnabled;
  LocationPermissionStatus permission;

  // What the user answers when asked for permission.
  LocationPermissionStatus answerToRequest;
  bool precise;

  int permissionRequests = 0;
  int streamsOpened = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;
  TrackingSettings? lastSettings;

  StreamController<LocationSample>? _positions;
  final StreamController<bool> _service = StreamController<bool>.broadcast();

  FakeLocationSource({
    this.serviceEnabled = true,
    this.permission = LocationPermissionStatus.granted,
    LocationPermissionStatus? answerToRequest,
    this.precise = true,
  }) : answerToRequest = answerToRequest ?? permission;

  // True while someone is listening to the position stream.
  bool get isStreaming => _positions != null && _positions!.hasListener;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permission;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    permissionRequests++;
    permission = answerToRequest;
    return permission;
  }

  @override
  Future<bool> hasPreciseAccuracy() async => precise;

  @override
  Stream<LocationSample> positionStream(TrackingSettings settings) {
    streamsOpened++;
    lastSettings = settings;
    final controller = StreamController<LocationSample>(sync: true);
    controller.onCancel = () {
      if (identical(_positions, controller)) _positions = null;
    };
    _positions = controller;
    return controller.stream;
  }

  @override
  Stream<bool> serviceEnabledChanges() => _service.stream;

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }

  void emit(LocationSample sample) => _positions?.add(sample);

  void emitError(LocationErrorKind kind) =>
      _positions?.addError(LocationStreamException(kind));

  void setServiceEnabled(bool enabled) {
    serviceEnabled = enabled;
    _service.add(enabled);
  }
}

LocationSample sampleAt(
  double latitude,
  double longitude,
  DateTime time, {
  double accuracy = 5,
}) => LocationSample(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: accuracy,
  recordedAt: time,
);
