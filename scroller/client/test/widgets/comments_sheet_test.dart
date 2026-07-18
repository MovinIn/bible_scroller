import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bible_scroller/models/auth_models.dart';
import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/auth_service.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/services/token_storage.dart';
import 'package:bible_scroller/state/auth_controller.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/widgets/comments_sheet.dart';

class _FakeReelsController extends ReelsController {
  _FakeReelsController()
      : super(
          api: ApiClient(deviceId: 'test-device'),
          storage: StorageService(),
        );

  @override
  Future<List<Comment>> loadComments(int reelId) async => const [];
}

class _NoopAuthService extends AuthService {
  _NoopAuthService()
      : super(
          api: _NoopAuthApi(),
          storage: InMemoryTokenStorage(),
          googleSignIn: _NoopGoogle(),
        );
}

class _NoopAuthApi implements AuthApi {
  @override
  String? accessToken;

  @override
  String get deviceId => 'd';

  @override
  Future<AuthUser> fetchMe() => throw UnimplementedError();

  @override
  Future<AuthSession> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> resendVerification({required String email}) =>
      throw UnimplementedError();

  @override
  Future<AuthSession> signInWithGoogleIdToken(String idToken) =>
      throw UnimplementedError();

  @override
  Future<AuthSession> verifyEmail({required String email, required String code}) =>
      throw UnimplementedError();
}

class _NoopGoogle implements GoogleSignInGateway {
  @override
  Future<String?> getIdToken() async => null;

  @override
  Future<void> signOut() async {}
}

const _reel = Reel(
  id: 1,
  reference: 'John 3:16',
  book: 'John',
  chapter: 3,
  startVerse: 16,
  endVerse: 16,
  slug: 'John_3_16-16',
  imageUrl: 'https://example.com/image.png',
  iqBookId: '43',
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
);

Widget _harness({required AuthController auth, required ReelsController reels}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: reels),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CommentsSheet(reel: _reel, controller: reels),
      ),
    ),
  );
}

AuthController _loggedOutAuth() => AuthController(authService: _NoopAuthService());

AuthController _loggedInAuth() {
  return AuthController(authService: _NoopAuthService())
    ..accessToken = 'tok'
    ..currentUser = const AuthUser(
      id: '1',
      displayName: 'User',
      email: 'u@example.com',
      emailVerified: true,
    );
}

void main() {
  testWidgets('hides comment composer when user is signed out', (tester) async {
    await tester.pumpWidget(
      _harness(auth: _loggedOutAuth(), reels: _FakeReelsController()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.send), findsNothing);
  });

  testWidgets('shows sign in to comment prompt when user is signed out', (tester) async {
    await tester.pumpWidget(
      _harness(auth: _loggedOutAuth(), reels: _FakeReelsController()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sign_in_to_comment')), findsOneWidget);
    expect(find.textContaining('Sign in'), findsWidgets);
  });

  testWidgets('shows comment composer when user is signed in', (tester) async {
    await tester.pumpWidget(
      _harness(auth: _loggedInAuth(), reels: _FakeReelsController()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.byKey(const Key('sign_in_to_comment')), findsNothing);
  });

  testWidgets('opens auth sheet when sign in to comment is tapped', (tester) async {
    await tester.pumpWidget(
      _harness(auth: _loggedOutAuth(), reels: _FakeReelsController()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sign_in_to_comment')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth_email_field')), findsOneWidget);
  });
}
