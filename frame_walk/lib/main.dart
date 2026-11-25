import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'frontend/navigation/stop_notification_router.dart';
import 'frontend/screens/auth_gate.dart';
import 'frontend/theme/app_theme.dart';
import 'backend/providers/profile_provider.dart';
import 'backend/providers/route_provider.dart';
import 'backend/services/bookmark_store.dart';
import 'backend/services/stop_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final notificationRouter = StopNotificationRouter(
    navigatorKey: GlobalKey<NavigatorState>(),
    signedInUserId: () async {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((user) => user != null);
      return user!.uid;
    },
  );
  // Before runApp so a tap on a notification is never missed. Taps while
  // FrameWalk is running (on screen or in the background) arrive here.
  final notifications = LocalStopNotificationService();
  await notifications.initialize(onTap: notificationRouter.handleTap);

  runApp(FrameWalkApp(navigatorKey: notificationRouter.navigatorKey));

  // A tap that launched FrameWalk from closed is reported separately.
  notificationRouter.handleTap(await notifications.launchPayload());
}

class FrameWalkApp extends StatelessWidget {
  const FrameWalkApp({super.key, this.navigatorKey});

  // Lets a tapped notification open the walk screen from outside the widget
  // tree (see StopNotificationRouter).
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RouteProvider(
            bookmarkStore: SharedPreferencesBookmarkStore(),
            userIds: FirebaseAuth.instance.authStateChanges().map(
              (user) => user?.uid,
            ),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ],
      child: MaterialApp(
        title: 'FrameWalk',
        navigatorKey: navigatorKey,
        theme: AppTheme.lightTheme,
        home: const AuthGate(),
      ),
    );
  }
}
