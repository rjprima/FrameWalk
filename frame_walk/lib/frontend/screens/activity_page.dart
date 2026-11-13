import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/route_provider.dart';
import '../widgets/completed_walks_list.dart';
import '../widgets/route_card.dart';
import 'route_info_page.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  // 0 = Previous Walks, 1 = Saved Walks
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'FrameWalk',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E9DF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _buildTabButton(label: 'Previous Walks', index: 0),
                _buildTabButton(label: 'Saved Walks', index: 1),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _selectedTab == 0 ? 'Previous Walks' : 'Saved Walks',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _selectedTab == 0
              ? const CompletedWalksList()
              : Consumer<RouteProvider>(
                  builder: (context, provider, _) {
                    final savedRoutes = provider.bookmarkedRoutes;
                    if (savedRoutes.isEmpty) {
                      return const Center(child: Text('No saved walks yet.'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: savedRoutes.length,
                      itemBuilder: (context, index) {
                        final route = savedRoutes[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RouteCard(
                            route: route,
                            onTap: () => RouteInfoPage.open(context, route),
                            onBookmarkTap: () =>
                                provider.toggleBookmark(route.id),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabButton({required String label, required int index}) {
    final isSelected = _selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF195B50) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: isSelected ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}