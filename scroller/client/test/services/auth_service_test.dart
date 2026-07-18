import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/auth_models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/auth_service.dart';
import 'package:bible_scroller/services/token_storage.dart';

class _RecordingApi implements AuthApi {
  @override
  String? accessToken;

  AuthUser? meUser;
  ApiException? meError;

  @override
  String get deviceId => 'device';

  @override
  Future<AuthUser> fetchMe() async {
    if (meError != null) {
      throw meError!;
    }
    return meUser!;
  }

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
  Future<void> resendVerification({required String email}) => throw UnimplementedError();

  @override
  Future<AuthSession> signInWithGoogleIdToken(String idToken) => throw UnimplementedError();

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

void main() {
  test('returns_session_when_stored_token_and_me_succeed', () async {
    final storage = InMemoryTokenStorage();
    await storage.saveToken('good-token');
    final api = _RecordingApi()
      ..meUser = const AuthUser(
        id: '1',
        displayName: 'User',
        email: 'u@example.com',
        emailVerified: true,
      );
    final service = AuthService(
      api: api,
      storage: storage,
      googleSignIn: _NoopGoogle(),
    );

    final session = await service.restoreSession();

    expect(session?.accessToken, 'good-token');
    expect(session?.user.email, 'u@example.com');
    expect(api.accessToken, 'good-token');
  });

  test('clears_token_when_me_returns_401', () async {
    final storage = InMemoryTokenStorage();
    await storage.saveToken('bad-token');
    final api = _RecordingApi()..meError = ApiException(401, '{"detail":"Invalid"}');
    final service = AuthService(
      api: api,
      storage: storage,
      googleSignIn: _NoopGoogle(),
    );

    final session = await service.restoreSession();

    expect(session, isNull);
    expect(await storage.readToken(), isNull);
    expect(api.accessToken, isNull);
  });

  test('throws_sign_in_cancelled_when_google_returns_null_token', () async {
    final service = AuthService(
      api: _RecordingApi(),
      storage: InMemoryTokenStorage(),
      googleSignIn: _NoopGoogle(),
    );

    await expectLater(service.signInWithGoogle(), throwsA(isA<SignInCancelledException>()));
  });
}
