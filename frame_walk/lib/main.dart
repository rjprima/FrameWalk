import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'frontend/screens/auth_gate.dart';
import 'frontend/theme/app_theme.dart';
import 'backend/providers/profile_provider.dart';
import 'backend/providers/route_provider.dart';
import 'backend/services/bookmark_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FrameWalkApp());
}

class FrameWalkApp extends StatelessWidget {
  const FrameWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RouteProvider(
            bookmarkStore: SharedPreferencesBookmarkStore(),
            userIds: FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ],
      child: MaterialApp(
        title: 'FrameWalk',
        theme: AppTheme.lightTheme,
        home: const AuthGate(),
      ),
    );
  }
}
