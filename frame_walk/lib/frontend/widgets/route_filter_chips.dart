
import 'package:flutter/material.dart';

class RouteFilterChips extends StatelessWidget {
  const RouteFilterChips({
    super.key,
    required this.duration,
    required this.distance,
    required this.scenery,
    required this.onDurationChanged,
    required this.onDistanceChanged,
    required this.onSceneryChanged,
  });

  final String duration;
  final String distance;
  final String scenery;

  final ValueChanged<String> onDurationChanged;
  final ValueChanged<String> onDistanceChanged;
  final ValueChanged<String> onSceneryChanged;

  static const Color lightGreen = Color(0xFFE2E9DF);
  static const Color darkGreen = Color(0xFF195B50);

  Widget _buildChip({
    required String label,
    required String selectedValue,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      itemBuilder: (context) => options.map((option) {
        return PopupMenuItem<String>(
          value: option,
          child: Text(option),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selectedValue == label
              ? lightGreen
              : darkGreen,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedValue == label
                  ? label
                  : selectedValue,
              style: TextStyle(
                fontSize: 12,
                color: selectedValue == label
                    ? Colors.black87
                    : Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: selectedValue == label
                  ? Colors.black87
                  : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildChip(
            label: 'Any duration',
            selectedValue: duration,
            options: const [
              'Any duration',
              '0-15 min',
              '15-30 min',
              '30+ min',
            ],
            onSelected: onDurationChanged,
          ),
          const SizedBox(width: 8),
          _buildChip(
            label: 'Any distance',
            selectedValue: distance,
            options: const [
              'Any distance',
              'Under 1 mi',
              '1-2 mi',
              '2+ mi',
            ],
            onSelected: onDistanceChanged,
          ),
          const SizedBox(width: 8),
          _buildChip(
            label: 'Any scenery',
            selectedValue: scenery,
            options: const [
              'Any scenery',
              'Architecture',
              'Nature',
              'Water',
              'Urban',
            ],
            onSelected: onSceneryChanged,
          ),
        ],
      ),
    );
  }
}
