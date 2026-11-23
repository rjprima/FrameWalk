import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/providers/route_provider.dart';
import 'package:frame_walk/backend/services/bookmark_store.dart';
import 'package:frame_walk/backend/services/route_manager.dart';

class MemoryBookmarkStore implements BookmarkStore {
  final Map<String, List<String>> data = {};
  @override
  Future<List<String>> read(String uid) async => List.of(data[uid] ?? []);
  @override
  Future<void> write(String uid, List<String> ids) async => data[uid] = List.of(ids);
}

RouteProvider newProvider(BookmarkStore store) => RouteProvider(
  seedMockData: false,
  bookmarkStore: store,
)..addRoute(WalkingRoute(id: 'a', name: 'Walk A', stopIds: []))
 ..addRoute(WalkingRoute(id: 'b', name: 'Walk B', stopIds: []));

void main() {
  test('bookmark survives provider recreation (simulated app restart)', () async {
    final store = MemoryBookmarkStore();
    final first = newProvider(store);
    await first.loadBookmarksForUser('alice');
    first.toggleBookmark('a');
    await first.bookmarksSaved;
    first.dispose();
    final restarted = newProvider(store);
    await restarted.loadBookmarksForUser('alice');
    expect(restarted.isBookmarked('a'), isTrue);
    expect(restarted.isBookmarked('b'), isFalse);
    restarted.dispose();
  });

  test('unbookmark also persists', () async {
    final store = MemoryBookmarkStore();
    final provider = newProvider(store);
    await provider.loadBookmarksForUser('alice');
    provider.toggleBookmark('a');
    provider.toggleBookmark('a');
    await provider.bookmarksSaved;
    final restarted = newProvider(store);
    await restarted.loadBookmarksForUser('alice');
    expect(restarted.bookmarkedRoutes, isEmpty);
    provider.dispose();
    restarted.dispose();
  });

  test('bookmarks are isolated by account and cleared on logout', () async {
    final store = MemoryBookmarkStore();
    final provider = newProvider(store);
    await provider.loadBookmarksForUser('alice');
    provider.toggleBookmark('a');
    await provider.bookmarksSaved;
    await provider.loadBookmarksForUser(null);
    expect(provider.bookmarkedRoutes, isEmpty);
    await provider.loadBookmarksForUser('bob');
    expect(provider.bookmarkedRoutes, isEmpty);
    provider.toggleBookmark('b');
    await provider.bookmarksSaved;
    await provider.loadBookmarksForUser('alice');
    expect(provider.isBookmarked('a'), isTrue);
    expect(provider.isBookmarked('b'), isFalse);
    provider.dispose();
  });

  test('unknown route ID does not save a bookmark', () async {
    final store = MemoryBookmarkStore();
    final provider = newProvider(store);
    await provider.loadBookmarksForUser('alice');
    provider.toggleBookmark('missing');
    await provider.bookmarksSaved;
    expect(store.data['alice'], isNull);
    provider.dispose();
  });
}
