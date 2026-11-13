import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/auth_service.dart';
import 'package:frame_walk/frontend/screens/account_page.dart';
import 'package:frame_walk/frontend/screens/auth_gate.dart';
import 'package:frame_walk/frontend/screens/create_account_page.dart';
import 'package:frame_walk/frontend/screens/landing_page.dart';
import 'package:frame_walk/frontend/screens/login_page.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;
  late AuthService service;

  setUp(() {
    auth = MockFirebaseAuth();
    firestore = FakeFirebaseFirestore();
    service = AuthService(auth: auth, firestore: firestore);
  });

  // Puts the page on top of a root route, the way the app reaches it.
  Future<void> openPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page),
            ),
            child: const Text('Root'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Root'));
    await tester.pumpAndSettle();
  }

  Future<void> enterField(WidgetTester tester, String hint, String text) {
    return tester.enterText(find.widgetWithText(TextFormField, hint), text);
  }

  Future<void> submit(WidgetTester tester, String buttonLabel) async {
    await tester.tap(find.widgetWithText(ElevatedButton, buttonLabel));
    await tester.pumpAndSettle();
  }

  group('LoginPage', () {
    testWidgets('returns to the root route after logging in', (tester) async {
      await openPage(tester, LoginPage(authService: service));
      await enterField(tester, 'you@example.com', 'walker@example.com');
      await enterField(tester, 'Enter your password', 'password123');

      await submit(tester, 'Log In');

      expect(auth.currentUser, isNotNull);
      expect(find.text('Root'), findsOneWidget);
    });

    testWidgets('stays on the page and shows the error', (tester) async {
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));
      await openPage(tester, LoginPage(authService: service));
      await enterField(tester, 'you@example.com', 'walker@example.com');
      await enterField(tester, 'Enter your password', 'wrong-password');

      await submit(tester, 'Log In');

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('does not submit an invalid form', (tester) async {
      await openPage(tester, LoginPage(authService: service));

      await submit(tester, 'Log In');

      expect(find.text('Please enter your email'), findsOneWidget);
      expect(auth.currentUser, isNull);
    });
  });

  group('CreateAccountPage', () {
    Future<void> fillForm(
      WidgetTester tester, {
      required String username,
    }) async {
      await enterField(tester, 'Choose a username', username);
      await enterField(tester, 'you@example.com', 'walker@example.com');
      await enterField(tester, 'Create a password', 'password123');
    }

    testWidgets('creates the account and returns to the root route', (
      tester,
    ) async {
      await openPage(tester, CreateAccountPage(authService: service));
      await fillForm(tester, username: 'walker');

      await submit(tester, 'Create Account');

      expect(auth.currentUser, isNotNull);
      expect(find.text('Root'), findsOneWidget);
    });

    testWidgets('stays on the page when the username is taken', (tester) async {
      await firestore.collection('usernames').doc('walker').set({'uid': 'x'});
      await openPage(tester, CreateAccountPage(authService: service));
      await fillForm(tester, username: 'Walker');

      await submit(tester, 'Create Account');

      expect(find.text('That username is already taken.'), findsOneWidget);
      expect(find.byType(CreateAccountPage), findsOneWidget);
    });

    testWidgets('rejects usernames with unsupported characters', (
      tester,
    ) async {
      await openPage(tester, CreateAccountPage(authService: service));
      await fillForm(tester, username: 'not/valid');

      await submit(tester, 'Create Account');

      expect(
        find.text('Use 3-20 letters, numbers, or underscores'),
        findsOneWidget,
      );
      expect(auth.currentUser, isNull);
    });
  });

  group('AuthGate', () {
    testWidgets('shows the landing page when signed out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AuthGate(authService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LandingPage), findsOneWidget);
    });
  });

  testWidgets('AccountPage logs the user out', (tester) async {
    await service.logIn(email: 'walker@example.com', password: 'password123');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccountPage(authService: service)),
      ),
    );

    await submit(tester, 'Log Out');

    expect(auth.currentUser, isNull);
  });
}
