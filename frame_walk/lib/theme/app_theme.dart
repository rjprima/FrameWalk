
import 'package:flutter/material.dart';

// Theme to be used for entire app
class AppTheme {

  static const teal = Color(0xFF195B50);
  static const cream = Color(0xFFFAF8F2);
  static const black = Color(0xFF171717);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        surface: cream,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle( // For landing page title
          fontSize: 38,
          fontWeight: FontWeight.bold,
          color: black,
        ),
        headlineMedium: TextStyle( 
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: black,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: black,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}
