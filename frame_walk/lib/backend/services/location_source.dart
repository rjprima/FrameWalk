import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/location_point.dart';

// Whether FrameWalk can start recording a walk right now.
enum LocationReadiness {
  ready,

  // Location services (GPS) are turned off for the whole device.
  serviceDisabled,

  // The user said no, but FrameWalk may ask again.
  denied,

  // The user said "don't ask again". Only the system settings can fix this.
  deniedForever,

  // Android 12+ / iOS 14+: the user allowed approximate location only, which
  // is too coarse (often 1-3 km) to tell when someone reaches a stop.
  approximateOnly,

  // The platform couldn't report a permission state.
  unavailable,
}

enum LocationPermissionStatus { granted, denied, deniedForever, unknown }

// Why the location stream stopped delivering readings.
enum LocationErrorKind { serviceDisabled, permissionDenied, other }

class LocationStreamException implements Exception {
  final LocationErrorKind kind;
  final String message;

  const LocationStreamException(this.kind, [this.message = '']);

  @override
  String toString() => 'LocationStreamException($kind): $message';
}

// How often to ask for location while walking.
//
// Battery: walking is slow (~1.4 m/s), so a 10 m distance filter means at most
// one reading every ~7 s and none while standing still. High accuracy is
// still needed because stops are only tens of meters apart.
class TrackingSettings {
  final double distanceFilterMeters;

  // Android only: the fastest the fused location provider may report.
  final Duration androidInterval;

  const TrackingSettings({
    this.distanceFilterMeters = 10,
    this.androidInterval = const Duration(seconds: 5),
  });
}

// Everything FrameWalk needs from the device's location services. The rest of
// the app depends on this rather than on geolocator, so it can be faked in
// tests.
abstract class LocationSource {
  Future<bool> isServiceEnabled();
  Future<LocationPermissionStatus> checkPermission();
  Future<LocationPermissionStatus> requestPermission();

  // False when the user granted approximate location only.
  Future<bool> hasPreciseAccuracy();

  // Emits readings until cancelled. Errors are [LocationStreamException]s.
  Stream<LocationSample> positionStream(TrackingSettings settings);

  // Emits true/false when the user turns device location services on or off.
  Stream<bool> serviceEnabledChanges();

  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

// Checks services and permission in the order the user needs to fix them.
// When [request] is true and permission hasn't been decided, asks the user.
Future<LocationReadiness> checkLocationReadiness(
  LocationSource source, {
  bool request = true,
}) async {
  if (!await source.isServiceEnabled()) {
    return LocationReadiness.serviceDisabled;
  }

  var permission = await source.checkPermission();
  if (permission == LocationPermissionStatus.denied && request) {
    permission = await source.requestPermission();
  }
  switch (permission) {
    case LocationPermissionStatus.denied:
      return LocationReadiness.denied;
    case LocationPermissionStatus.deniedForever:
      return LocationReadiness.deniedForever;
    case LocationPermissionStatus.unknown:
      return LocationReadiness.unavailable;
    case LocationPermissionStatus.granted:
      break;
  }

  if (!await source.hasPreciseAccuracy()) {
    return LocationReadiness.approximateOnly;
  }
  return LocationReadiness.ready;
}

// Foreground-only location using the geolocator plugin.
//
// No foreground service and no background permission are configured, so the
// OS stops or heavily throttles updates once FrameWalk leaves the screen.
// WalkTrackingService pauses the stream itself when that happens.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      _mapPermission(await Geolocator.checkPermission());

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    try {
      return _mapPermission(await Geolocator.requestPermission());
    } on PermissionRequestInProgressException {
      return LocationPermissionStatus.denied;
    } on PermissionDefinitionsNotFoundException {
      return LocationPermissionStatus.unknown;
    }
  }

  @override
  Future<bool> hasPreciseAccuracy() async {
    try {
      return await Geolocator.getLocationAccuracy() !=
          LocationAccuracyStatus.reduced;
    } on Exception {
      // Older platforms have no approximate-only option.
      return true;
    }
  }

  @override
  Stream<LocationSample> positionStream(TrackingSettings settings) {
    return Geolocator.getPositionStream(
      locationSettings: _platformSettings(settings),
    ).map(_toSample).handleError(
      (Object error, StackTrace stackTrace) {
        throw _mapError(error);
      },
    );
  }

  @override
  Stream<bool> serviceEnabledChanges() {
    if (kIsWeb) return const Stream.empty();
    return Geolocator.getServiceStatusStream()
        .map((status) => status == ServiceStatus.enabled);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  static LocationSettings _platformSettings(TrackingSettings settings) {
    final distanceFilter = settings.distanceFilterMeters.round();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: settings.androidInterval,
        // No foregroundNotificationConfig: background tracking is not
        // enabled. See README "GPS tracking".
      );
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        activityType: ActivityType.fitness,
        // Off: users stand still at photo stops, and once iOS auto-pauses
        // updates it doesn't resume them by itself. Tracking only runs while
        // FrameWalk is on screen, so keeping GPS on costs little extra.
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
  }

  static LocationSample _toSample(Position position) => LocationSample(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        recordedAt: position.timestamp,
        // Negative or zero speeds mean "unknown" on most devices.
        speedMetersPerSecond: position.speed > 0 ? position.speed : null,
      );

  static LocationPermissionStatus _mapPermission(LocationPermission value) {
    switch (value) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.unknown;
    }
  }

  static LocationStreamException _mapError(Object error) {
    if (error is LocationStreamException) return error;
    if (error is LocationServiceDisabledException) {
      return const LocationStreamException(LocationErrorKind.serviceDisabled);
    }
    if (error is PermissionDeniedException) {
      return LocationStreamException(
        LocationErrorKind.permissionDenied,
        error.message ?? '',
      );
    }
    return LocationStreamException(LocationErrorKind.other, '$error');
  }
}
