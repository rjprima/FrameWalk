import 'package:shared_preferences/shared_preferences.dart';

/// Local, per-device bookmark persistence. Firebase is used only to identify
/// the signed-in account; no bookmark data is written to Firestore.
abstract class BookmarkStore {
  Future<List<String>> read(String userId);
  Future<void> write(String userId, List<String> routeIds);
}

class SharedPreferencesBookmarkStore implements BookmarkStore {
  String _key(String userId) => 'framewalk.bookmarks.v1.$userId';

  @override
  Future<List<String>> read(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(userId)) ?? <String>[];
  }

  @override
  Future<void> write(String userId, List<String> routeIds) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(_key(userId), routeIds);
    if (!saved) throw StateError('Could not save route bookmarks locally');
  }
}
