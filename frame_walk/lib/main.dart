
import 'package:flutter/material.dart';
import 'frontend/screens/landing_page.dart';
import 'frontend/theme/app_theme.dart';

void main() {
  runApp(const FrameWalkApp());
}

class FrameWalkApp extends StatelessWidget {
  const FrameWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FrameWalk',
      theme: AppTheme.lightTheme,
      home: const LandingPage(),
    );
  }
}
