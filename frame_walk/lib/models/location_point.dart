import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

// A latitude/longitude pair with no map-library dependency, so backend code
// and tests don't need google_maps_flutter.
class GeoCoordinate {
  final double latitude;
  final double longitude;

  const GeoCoordinate(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoCoordinate($latitude, $longitude)';
}

// One reading from the device's location provider, before FrameWalk decides
// whether to keep it.
class LocationSample {
  final double latitude;
  final double longitude;

  // Radius of 68% confidence, in meters, as reported by the OS.
  final double accuracyMeters;
  final DateTime recordedAt;

  // Null when the OS doesn't report it.
  final double? speedMetersPerSecond;

  const LocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.recordedAt,
    this.speedMetersPerSecond,
  });

  GeoCoordinate get coordinate => GeoCoordinate(latitude, longitude);
}

// A location FrameWalk kept during a walk. Stored at
// users/{uid}/walks/{walkId}/locationPoints/{id}.
//
// [id] comes from the point's position in the walk, so writing the same point
// twice (for example, retrying after an error) can't create a duplicate.
class LocationPoint {
  final String id;
  final int sequence;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime recordedAt;
  final double? speedMetersPerSecond;

  const LocationPoint({
    required this.id,
    required this.sequence,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.recordedAt,
    this.speedMetersPerSecond,
  });

  factory LocationPoint.fromSample(int sequence, LocationSample sample) {
    return LocationPoint(
      id: idForSequence(sequence),
      sequence: sequence,
      latitude: sample.latitude,
      longitude: sample.longitude,
      accuracyMeters: sample.accuracyMeters,
      recordedAt: sample.recordedAt,
      speedMetersPerSecond: sample.speedMetersPerSecond,
    );
  }

  // Zero-padded so document IDs sort in the order the points were recorded.
  static String idForSequence(int sequence) =>
      'p${sequence.toString().padLeft(6, '0')}';

  GeoCoordinate get coordinate => GeoCoordinate(latitude, longitude);

  Map<String, dynamic> toMap() => {
        'sequence': sequence,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'recordedAt': Timestamp.fromDate(recordedAt),
        if (speedMetersPerSecond != null)
          'speedMetersPerSecond': speedMetersPerSecond,
      };

  factory LocationPoint.fromMap(String id, Map<String, dynamic> map) {
    return LocationPoint(
      id: id,
      sequence: (map['sequence'] as num).toInt(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyMeters: (map['accuracyMeters'] as num).toDouble(),
      recordedAt: readTimestamp(map['recordedAt'])!,
      speedMetersPerSecond: (map['speedMetersPerSecond'] as num?)?.toDouble(),
    );
  }
}

// Firestore returns Timestamps; fakes may return DateTimes.
DateTime? readTimestamp(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  throw FormatException('Expected a timestamp but found $value');
}

// Distance helpers. Accurate to well under a meter at walking scale.
class GeoMath {
  static const double earthRadiusMeters = 6371000;

  static double distanceMeters(GeoCoordinate a, GeoCoordinate b) {
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final dLat = lat2 - lat1;
    final dLng = _radians(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
  }

  // Shortest distance from [point] to the path through [path]. Uses a flat
  // projection around [point], which is fine for campus-sized routes.
  static double distanceToPathMeters(
    GeoCoordinate point,
    List<GeoCoordinate> path,
  ) {
    if (path.isEmpty) return double.infinity;
    if (path.length == 1) return distanceMeters(point, path.first);

    final cosLat = math.cos(_radians(point.latitude));
    ({double x, double y}) project(GeoCoordinate c) => (
          x: _radians(c.longitude - point.longitude) *
              cosLat *
              earthRadiusMeters,
          y: _radians(c.latitude - point.latitude) * earthRadiusMeters,
        );

    var best = double.infinity;
    for (var i = 0; i < path.length - 1; i++) {
      final a = project(path[i]);
      final b = project(path[i + 1]);
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final lengthSquared = dx * dx + dy * dy;
      // The point is at the origin of the projection.
      final t = lengthSquared == 0
          ? 0.0
          : ((-a.x * dx + -a.y * dy) / lengthSquared).clamp(0.0, 1.0);
      final cx = a.x + t * dx;
      final cy = a.y + t * dy;
      best = math.min(best, math.sqrt(cx * cx + cy * cy));
    }
    return best;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
