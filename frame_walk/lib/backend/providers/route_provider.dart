import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/mock_route_data.dart';
import '../services/bookmark_store.dart';
import '../services/route_manager.dart';

/// Single source of truth for routes and bookmarks.
class RouteProvider extends ChangeNotifier {
  static const anyDuration = 'Any duration';
  static const anyDistance = 'Any distance';
  static const anyScenery = 'Any scenery';

  RouteProvider({
    RouteManager? manager,
    bool seedMockData = true,
    BookmarkStore? bookmarkStore,
    Stream<String?>? userIds,
  }) : _manager = manager ?? RouteManager(),
       _bookmarkStore = bookmarkStore {
    if (seedMockData) {
      for (final route in MockRouteData.routes) {
        _manager.addRoute(route);
      }
    }
    if (bookmarkStore != null && userIds != null) {
      _authSubscription = userIds.listen((id) { unawaited(loadBookmarksForUser(id)); });
    }
  }

  final RouteManager _manager;
  final BookmarkStore? _bookmarkStore;
  StreamSubscription<String?>? _authSubscription;
  String? _userId;
  int _loadVersion = 0;
  Future<void> _pendingWrite = Future<void>.value();
  bool _disposed = false;
  bool bookmarksLoading = false;
  Object? bookmarkError;

  List<WalkingRoute> get routes => _manager.getAllRoutes();
  List<WalkingRoute> get bookmarkedRoutes => _manager.getBookmarkedRoutes();

  WalkingRoute? byId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    return _manager.getRoute(id);
  }

  bool isBookmarked(String id) => byId(id)?.isBookmarked ?? false;

  /// Load the bookmarks for this account. Calling with null clears them on logout.
  /// A version token prevents an old asynchronous read from leaking another
  /// account's bookmarks into the current session.
  Future<void> loadBookmarksForUser(String? userId) async {
    final version = ++_loadVersion;
    _userId = userId;
    bookmarksLoading = userId != null && _bookmarkStore != null;
    bookmarkError = null;
    for (final route in _manager.getAllRoutes()) {
      _manager.setBookmarked(route.id, false);
    }
    _notify();
    if (!bookmarksLoading) return;
    try {
      final savedIds = (await _bookmarkStore!.read(userId!)).toSet();
      if (_disposed || version != _loadVersion) return;
      for (final route in _manager.getAllRoutes()) {
        _manager.setBookmarked(route.id, savedIds.contains(route.id));
      }
    } catch (error) {
      if (_disposed || version != _loadVersion) return;
      bookmarkError = error;
    } finally {
      if (!_disposed && version == _loadVersion) {
        bookmarksLoading = false;
        _notify();
      }
    }
  }

  List<WalkingRoute> search({
    String query = '',
    String duration = anyDuration,
    String distance = anyDistance,
    String scenery = anyScenery,
  }) {
    final matchingRoutes = _manager.searchRoutes(query);
    final sceneryMatches = _manager.filterBySceneryTags(
      scenery == anyScenery ? const [] : [scenery],
    );
    final sceneryIds = sceneryMatches.map((route) => route.id).toSet();
    return matchingRoutes.where((route) {
      if (!sceneryIds.contains(route.id)) return false;
      final minutes = route.estimatedMinutes;
      final matchesDuration = switch (duration) {
        '0-15 min' => minutes <= 15,
        '15-30 min' => minutes > 15 && minutes <= 30,
        '30+ min' => minutes > 30,
        _ => true,
      };
      final miles = route.distanceMiles;
      final matchesDistance = switch (distance) {
        'Under 1 mi' => miles < 1,
        '1-2 mi' => miles >= 1 && miles <= 2,
        '2+ mi' => miles > 2,
        _ => true,
      };
      return matchesDuration && matchesDistance;
    }).toList();
  }

  void toggleBookmark(String routeId) {
    // Never overwrite saved bookmarks while they are still loading.
    if (bookmarksLoading || bookmarkError != null) return;
    if (!_manager.toggleBookmark(routeId)) return;
    _notify();
    final userId = _userId;
    final store = _bookmarkStore;
    if (userId == null || store == null) return;
    final ids = _manager.getBookmarkedRoutes().map((r) => r.id).toList();
    // Serialize writes so rapid taps cannot persist an older state last.
    _pendingWrite = _pendingWrite.catchError((Object _) {}).then((_) async {
      try {
        await store.write(userId, ids);
      } catch (error) {
        if (!_disposed && _userId == userId) {
          bookmarkError = error;
          _notify();
        }
      }
    });
  }

  /// Useful for callers/tests that need to await the last local write.
  Future<void> get bookmarksSaved => _pendingWrite;

  void addRoute(WalkingRoute route) {
    _manager.addRoute(route);
    _notify();
  }

  void removeRoute(String routeId) {
    if (_manager.removeRoute(routeId)) _notify();
  }

  void updateRoute(WalkingRoute route) {
    if (_manager.updateRoute(route)) _notify();
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _disposed = true;
    _loadVersion++;
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
