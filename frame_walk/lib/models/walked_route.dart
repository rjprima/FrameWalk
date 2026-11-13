import 'package:cloud_firestore/cloud_firestore.dart';

import 'location_point.dart';
import 'route_stop.dart';

// A Route is a predefined path (see PhotoRoute / WalkingRoute). A WalkedRoute
// is one occasion when a user actually walked one, and is stored at
// users/{userId}/walks/{id}. Its recorded GPS history lives in the
// locationPoints subcollection (see LocationPoint).
//
// The route's stops are copied in when the walk starts, so the history still
// makes sense if the route is edited later, and so photos can be matched to
// stop coordinates and walk times without looking the route up again.
enum WalkStatus {
  // Being walked right now. Has no completedAt.
  active,

  // Finished by the user. Only completed walks count as Walked-Routes.
  completed,
}

// FrameWalk records location only while the app is open on screen. Saved with
// each walk so gaps in its history can be explained later.
const String foregroundTrackingMode = 'foreground';

class WalkedRoute {
  final String id;
  final String userId;
  final String routeId;
  final String routeTitle;
  final WalkStatus status;
  final String trackingMode;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<WalkedStop> stops;
  final double distanceMeters;
  final int locationPointCount;
  final DateTime? lastLocationAt;

  WalkedRoute({
    required this.id,
    required this.userId,
    required this.routeId,
    required this.routeTitle,
    required this.status,
    required this.startedAt,
    required List<WalkedStop> stops,
    this.trackingMode = foregroundTrackingMode,
    this.completedAt,
    this.distanceMeters = 0,
    this.locationPointCount = 0,
    this.lastLocationAt,
  }) : stops = List.unmodifiable(stops) {
    if (id.trim().isEmpty) throw ArgumentError('Walk ID cannot be empty');
    if (routeId.trim().isEmpty) throw ArgumentError('Route ID cannot be empty');
    if (status == WalkStatus.completed && completedAt == null) {
      throw ArgumentError('A completed walk needs a completion time');
    }
    if (completedAt != null && completedAt!.isBefore(startedAt)) {
      throw ArgumentError('A walk cannot end before it starts');
    }
  }

  factory WalkedRoute.start({
    required String id,
    required String userId,
    required String routeId,
    required String routeTitle,
    required List<RouteStop> stops,
    required DateTime startedAt,
  }) {
    return WalkedRoute(
      id: id,
      userId: userId,
      routeId: routeId,
      routeTitle: routeTitle,
      status: WalkStatus.active,
      startedAt: startedAt,
      stops: stops.map(WalkedStop.fromRouteStop).toList(),
    );
  }

  bool get isCompleted => status == WalkStatus.completed;

  Duration? get duration => completedAt?.difference(startedAt);

  List<String> get stopIds => stops.map((stop) => stop.stopId).toList();

  List<String> get reachedStopIds => [
        for (final stop in stops)
          if (stop.reachedAt != null) stop.stopId,
      ];

  List<String> get promptIds => stops.map((stop) => stop.promptId).toList();

  WalkedRoute copyWith({
    WalkStatus? status,
    DateTime? completedAt,
    List<WalkedStop>? stops,
    double? distanceMeters,
    int? locationPointCount,
    DateTime? lastLocationAt,
  }) {
    return WalkedRoute(
      id: id,
      userId: userId,
      routeId: routeId,
      routeTitle: routeTitle,
      status: status ?? this.status,
      trackingMode: trackingMode,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      stops: stops ?? this.stops,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      locationPointCount: locationPointCount ?? this.locationPointCount,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
    );
  }

  // Marks [stopId] reached at [time], unless it was already reached.
  WalkedRoute withStopReached(String stopId, DateTime time) {
    return copyWith(
      stops: [
        for (final stop in stops)
          stop.stopId == stopId && stop.reachedAt == null
              ? stop.copyWithReachedAt(time)
              : stop,
      ],
    );
  }

  // Field names match the photo-gallery branch's WalkRecord (userId, routeId,
  // routeTitle, startedAt, completedAt, stopIds, promptIds, stops[].stopId,
  // stopName, latitude, longitude, prompts) so it can read these documents.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'routeId': routeId,
        'routeTitle': routeTitle,
        'status': status.name,
        'trackingMode': trackingMode,
        'startedAt': Timestamp.fromDate(startedAt),
        if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
        'stopIds': stopIds,
        'promptIds': promptIds,
        'reachedStopIds': reachedStopIds,
        'stops': stops.map((stop) => stop.toMap()).toList(),
        'distanceMeters': distanceMeters,
        'locationPointCount': locationPointCount,
        if (lastLocationAt != null)
          'lastLocationAt': Timestamp.fromDate(lastLocationAt!),
      };

  factory WalkedRoute.fromMap(String id, Map<String, dynamic> map) {
    return WalkedRoute(
      id: id,
      userId: map['userId'] as String,
      routeId: map['routeId'] as String,
      routeTitle: map['routeTitle'] as String? ?? '',
      status: WalkStatus.values.byName(map['status'] as String? ?? 'completed'),
      trackingMode: map['trackingMode'] as String? ?? foregroundTrackingMode,
      startedAt: readTimestamp(map['startedAt'])!,
      completedAt: readTimestamp(map['completedAt']),
      stops: ((map['stops'] as List?) ?? const [])
          .map((stop) =>
              WalkedStop.fromMap(Map<String, dynamic>.from(stop as Map)))
          .toList(),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      locationPointCount: (map['locationPointCount'] as num?)?.toInt() ?? 0,
      lastLocationAt: readTimestamp(map['lastLocationAt']),
    );
  }
}

// A route stop as it was when the walk started, plus when the user got there.
class WalkedStop {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;
  final String prompt;
  final DateTime? reachedAt;

  const WalkedStop({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    this.prompt = '',
    this.reachedAt,
  });

  factory WalkedStop.fromRouteStop(RouteStop stop) => WalkedStop(
        stopId: stop.id,
        stopName: stop.name,
        latitude: stop.latitude,
        longitude: stop.longitude,
        prompt: stop.prompt,
      );

  // Prompts don't have their own IDs yet, so a prompt is identified by its
  // stop and position. Same convention as the photo-gallery branch.
  String get promptId => '$stopId#0';

  GeoCoordinate get coordinate => GeoCoordinate(latitude, longitude);

  WalkedStop copyWithReachedAt(DateTime time) => WalkedStop(
        stopId: stopId,
        stopName: stopName,
        latitude: latitude,
        longitude: longitude,
        prompt: prompt,
        reachedAt: time,
      );

  Map<String, dynamic> toMap() => {
        'stopId': stopId,
        'stopName': stopName,
        'latitude': latitude,
        'longitude': longitude,
        'prompts': [
          {'id': promptId, 'text': prompt},
        ],
        'reachedAt': reachedAt == null ? null : Timestamp.fromDate(reachedAt!),
      };

  factory WalkedStop.fromMap(Map<String, dynamic> map) {
    final prompts = (map['prompts'] as List?) ?? const [];
    return WalkedStop(
      stopId: map['stopId'] as String,
      stopName: map['stopName'] as String? ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      prompt: prompts.isEmpty
          ? ''
          : (Map<String, dynamic>.from(prompts.first as Map)['text']
                  as String? ??
              ''),
      reachedAt: readTimestamp(map['reachedAt']),
    );
  }
}
