import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/auth_service.dart';
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

  Matcher failsWith(String message) => throwsA(
    isA<AuthFailure>().having((failure) => failure.message, 'message', message),
  );

  group('createAccount', () {
    test('stores account data, starting statistics at zero', () async {
      await service.createAccount(
        email: ' walker@example.com ',
        username: 'Walker_1',
        password: 'password123',
      );

      final uid = auth.currentUser!.uid;
      final account = await firestore.collection('users').doc(uid).get();
      expect(account.data()!['username'], 'Walker_1');
      expect(account.data()!['email'], 'walker@example.com');
      expect(account.data()!['routesCompleted'], 0);
      expect(account.data()!['photosTaken'], 0);
      expect(account.data()!.containsKey('password'), isFalse);
    });

    test('reserves the username in lowercase', () async {
      await service.createAccount(
        email: 'walker@example.com',
        username: 'Walker_1',
        password: 'password123',
      );

      final reservation = await firestore
          .collection('usernames')
          .doc('walker_1')
          .get();
      expect(reservation.data()!['uid'], auth.currentUser!.uid);
    });

    test(
      'rejects a taken username regardless of case and removes the user',
      () async {
        await firestore.collection('usernames').doc('walker_1').set({
          'uid': 'someone-else',
        });
        final signUpAuth = _TrackedSignUpAuth();
        service = AuthService(auth: signUpAuth, firestore: firestore);

        await expectLater(
          service.createAccount(
            email: 'walker@example.com',
            username: 'WALKER_1',
            password: 'password123',
          ),
          failsWith('That username is already taken.'),
        );

        expect(signUpAuth.newUser.wasDeleted, isTrue);
        expect((await firestore.collection('users').get()).docs, isEmpty);
      },
    );

    test('removes the new user when saving the account fails', () async {
      final signUpAuth = _TrackedSignUpAuth();
      service = AuthService(auth: signUpAuth, firestore: _FailingFirestore());

      await expectLater(
        service.createAccount(
          email: 'walker@example.com',
          username: 'walker',
          password: 'password123',
        ),
        failsWith(
          "We couldn't finish creating your account. Please try again.",
        ),
      );

      expect(signUpAuth.newUser.wasDeleted, isTrue);
    });

    test('signs out when the new user cannot be removed', () async {
      final signUpAuth = _TrackedSignUpAuth(deleteFails: true);
      service = AuthService(auth: signUpAuth, firestore: _FailingFirestore());

      await expectLater(
        service.createAccount(
          email: 'walker@example.com',
          username: 'walker',
          password: 'password123',
        ),
        throwsA(isA<AuthFailure>()),
      );

      expect(signUpAuth.didSignOut, isTrue);
    });

    test('shows a readable message when the email is in use', () async {
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      await expectLater(
        service.createAccount(
          email: 'walker@example.com',
          username: 'walker',
          password: 'password123',
        ),
        failsWith('An account with this email already exists.'),
      );
    });
  });

  group('logIn', () {
    test('signs in an existing user', () async {
      await service.logIn(email: 'walker@example.com', password: 'password123');

      expect(auth.currentUser, isNotNull);
    });

    test('uses one message for wrong credentials', () async {
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));

      await expectLater(
        service.logIn(email: 'walker@example.com', password: 'wrong-password'),
        failsWith('Incorrect email or password.'),
      );
    });

    test('shows a generic message for unknown errors', () async {
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'unexpected-code'));

      await expectLater(
        service.logIn(email: 'walker@example.com', password: 'password123'),
        failsWith('Something went wrong. Please try again.'),
      );
    });
  });

  test('logOut signs the user out', () async {
    await service.logIn(email: 'walker@example.com', password: 'password123');

    await service.logOut();

    expect(auth.currentUser, isNull);
  });
}

// MockUser.delete does nothing and MockFirebaseAuth creates its own user during
// sign-up, so these record what the service does to the new user.
// ignore: must_be_immutable
class _TrackedUser extends MockUser {
  final bool deleteFails;
  bool wasDeleted = false;

  _TrackedUser({required this.deleteFails}) : super(uid: 'new-user');

  @override
  Future<void> delete() async {
    if (deleteFails) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    wasDeleted = true;
  }
}

class _TrackedCredential extends Fake implements UserCredential {
  @override
  final User user;

  _TrackedCredential(this.user);
}

class _TrackedSignUpAuth extends MockFirebaseAuth {
  final _TrackedUser newUser;
  bool didSignOut = false;

  _TrackedSignUpAuth({bool deleteFails = false})
    : newUser = _TrackedUser(deleteFails: deleteFails);

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async => _TrackedCredential(newUser);

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}

class _FailingFirestore extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> updateFunction, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}
