import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/location_point.dart';
import '../../models/walked_route.dart';

// Firestore storage for walks the user has started or finished.
//
//   users/{uid}                                        routesCompleted += 1
//   users/{uid}/walks/{walkId}                         WalkedRoute
//   users/{uid}/walks/{walkId}/locationPoints/{id}     LocationPoint
//
// Predefined routes are not stored here; a walk only refers to one by
// routeId. Writes go to Firestore's offline cache first and sync when the
// device is online, so callers shouldn't block the UI waiting on them.
class WalkRepository {
  // Firestore allows up to 500 writes in one batch. Leaves room for the
  // walk-document update that goes with each batch of points.
  static const int _maxPointsPerBatch = 400;

  final FirebaseFirestore _firestore;

  WalkRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _walks(String userId) =>
      _firestore.collection('users').doc(userId).collection('walks');

  DocumentReference<Map<String, dynamic>> _walkDoc(WalkedRoute walk) =>
      _walks(walk.userId).doc(walk.id);

  CollectionReference<Map<String, dynamic>> _points(
    String userId,
    String walkId,
  ) =>
      _walks(userId).doc(walkId).collection('locationPoints');

  // A new unique walk ID. Generated on the device, so it works offline.
  String newWalkId(String userId) => _walks(userId).doc().id;

  Future<void> createWalk(WalkedRoute walk) {
    if (walk.status != WalkStatus.active) {
      throw ArgumentError('Only an active walk can be created');
    }
    return _walkDoc(walk).set({
      ...walk.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Saves recorded points and the walk's running totals together.
  Future<void> appendLocationPoints(
    WalkedRoute walk,
    List<LocationPoint> points,
  ) async {
    if (points.isEmpty) return;
    for (var start = 0; start < points.length; start += _maxPointsPerBatch) {
      final end = (start + _maxPointsPerBatch).clamp(0, points.length);
      final batch = _firestore.batch();
      for (final point in points.sublist(start, end)) {
        batch.set(_points(walk.userId, walk.id).doc(point.id), point.toMap());
      }
      batch.update(_walkDoc(walk), _progressFields(walk));
      await batch.commit();
    }
  }

  // Saves which stops have been reached, and when.
  Future<void> updateProgress(WalkedRoute walk) {
    return _walkDoc(walk).update(_progressFields(walk));
  }

  // Marks the walk completed and adds it to the user's completed-route count
  // in one write, so the two can't disagree.
  Future<void> completeWalk(WalkedRoute walk) {
    if (!walk.isCompleted) {
      throw ArgumentError('Walk must be marked completed first');
    }
    final batch = _firestore.batch()
      ..update(_walkDoc(walk), {
        ..._progressFields(walk),
        'status': WalkStatus.completed.name,
        'completedAt': Timestamp.fromDate(walk.completedAt!),
      })
      ..update(_firestore.collection('users').doc(walk.userId), {
        'routesCompleted': FieldValue.increment(1),
      });
    return batch.commit();
  }

  // Removes a cancelled walk and its location history. A cancelled walk was
  // never a Walked-Route, and its GPS trail shouldn't be kept.
  Future<void> deleteWalk(WalkedRoute walk) async {
    final points = await _points(walk.userId, walk.id).get();
    final refs = points.docs.map((doc) => doc.reference).toList();
    for (var start = 0; start < refs.length; start += _maxPointsPerBatch) {
      final end = (start + _maxPointsPerBatch).clamp(0, refs.length);
      final batch = _firestore.batch();
      for (final ref in refs.sublist(start, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
    await _walkDoc(walk).delete();
  }

  Future<WalkedRoute?> fetchWalk(String userId, String walkId) async {
    final doc = await _walks(userId).doc(walkId).get();
    final data = doc.data();
    return data == null ? null : WalkedRoute.fromMap(doc.id, data);
  }

  // Completed walks, newest first. Active walks have no completedAt, so the
  // ordering leaves them out without needing a composite index.
  Future<List<WalkedRoute>> fetchCompletedWalks(String userId) async {
    final snapshot = await _walks(userId)
        .orderBy('completedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => WalkedRoute.fromMap(doc.id, doc.data()))
        .where((walk) => walk.isCompleted)
        .toList();
  }

  Future<List<LocationPoint>> fetchLocationPoints(
    String userId,
    String walkId,
  ) async {
    final snapshot =
        await _points(userId, walkId).orderBy('sequence').get();
    return snapshot.docs
        .map((doc) => LocationPoint.fromMap(doc.id, doc.data()))
        .toList();
  }

  Map<String, dynamic> _progressFields(WalkedRoute walk) {
    final map = walk.toMap();
    return {
      'stops': map['stops'],
      'reachedStopIds': map['reachedStopIds'],
      'distanceMeters': map['distanceMeters'],
      'locationPointCount': map['locationPointCount'],
      if (map['lastLocationAt'] != null)
        'lastLocationAt': map['lastLocationAt'],
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
