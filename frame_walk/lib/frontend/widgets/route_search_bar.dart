
import 'package:flutter/material.dart';

class RouteSearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const RouteSearchBar({
    super.key,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search routes',
        prefixIcon: const Icon(Icons.menu),
        suffixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: const Color(0xFF195B50),
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIconColor: Colors.white,
        suffixIconColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
      style: const TextStyle(color: Colors.white),
    );
  }
}
