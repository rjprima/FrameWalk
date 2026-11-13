import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../backend/services/walk_repository.dart';
import '../../models/walked_route.dart';
import '../screens/walk_gallery_page.dart';

// The signed-in user's completed walks, newest first. Tapping one opens its
// photo gallery. Pull down to refresh after finishing a walk. A minimal list
// for testing the photo backend.
class CompletedWalksList extends StatefulWidget {
  const CompletedWalksList({super.key, this.auth, this.repository});

  final FirebaseAuth? auth;
  final WalkRepository? repository;

  @override
  State<CompletedWalksList> createState() => _CompletedWalksListState();
}

class _CompletedWalksListState extends State<CompletedWalksList> {
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final WalkRepository _repository = widget.repository ?? WalkRepository();
  late Future<List<WalkedRoute>> _walks = _load();

  Future<List<WalkedRoute>> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    return _repository.fetchCompletedWalks(uid);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _walks = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WalkedRoute>>(
      future: _walks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your walks.'),
                TextButton(onPressed: _refresh, child: const Text('Try again')),
              ],
            ),
          );
        }
        final walks = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: walks.isEmpty
              // A scrollable, so pull-to-refresh still works when empty.
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No previous walks yet.')),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: walks.length,
                  itemBuilder: (context, index) => _WalkTile(
                    walk: walks[index],
                    onTap: () async {
                      await WalkGalleryPage.open(context, walks[index].id);
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _WalkTile extends StatelessWidget {
  const _WalkTile({required this.walk, required this.onTap});

  final WalkedRoute walk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(walk.completedAt!.toLocal());
    final stops = walk.stops.length;
    return Card(
      child: ListTile(
        title: Text(walk.routeTitle.isEmpty ? 'Walk' : walk.routeTitle),
        subtitle: Text('$date · $stops stop${stops == 1 ? '' : 's'}'),
        trailing: const Icon(Icons.photo_library_outlined),
        onTap: onTap,
      ),
    );
  }
}
