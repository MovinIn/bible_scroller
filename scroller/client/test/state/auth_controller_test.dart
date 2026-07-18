import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/auth_models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/auth_service.dart';
import 'package:bible_scroller/services/token_storage.dart';
import 'package:bible_scroller/state/auth_controller.dart';

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          api: _UnusedApi(),
          storage: InMemoryTokenStorage(),
          googleSignIn: _FakeGoogleSignIn(),
        );

  AuthUser? nextUser;
  String? nextToken;
  Object? loginError;
  AuthSession? restoreResult;
  Object? restoreError;
  bool registerReturnsVerification = true;

  @override
  Future<RegisterResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (registerReturnsVerification) {
      return RegisterResult.verificationRequired(email);
    }
    throw StateError('unexpected');
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (loginError != null) {
      throw loginError!;
    }
    final session = AuthSession(
      accessToken: nextToken ?? 'token',
      user: nextUser ??
          AuthUser(
            id: '1',
            displayName: 'User',
            email: email,
            emailVerified: true,
          ),
    );
    await storage.saveToken(session.accessToken);
    return session;
  }

  @override
  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async {
    final session = AuthSession(
      accessToken: nextToken ?? 'verified-token',
      user: nextUser ??
          AuthUser(
            id: '1',
            displayName: 'User',
            email: email,
            emailVerified: true,
          ),
    );
    await storage.saveToken(session.accessToken);
    return session;
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    final session = AuthSession(
      accessToken: nextToken ?? 'google-token',
      user: nextUser ??
          const AuthUser(
            id: 'g1',
            displayName: 'Google User',
            email: 'g@example.com',
            emailVerified: true,
          ),
    );
    await storage.saveToken(session.accessToken);
    return session;
  }

  @override
  Future<AuthSession?> restoreSession() async {
    if (restoreError != null) {
      throw restoreError!;
    }
    return restoreResult;
  }

  @override
  Future<void> signOut() async {
    await storage.clearToken();
  }

  @override
  Future<void> resendVerification(String email) async {}
}

class _UnusedApi implements AuthApi {
  @override
  String? accessToken;

  @override
  String get deviceId => 'device';

  @override
  Future<AuthSession> login({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> resendVerification({required String email}) {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> signInWithGoogleIdToken(String idToken) {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> verifyEmail({required String email, required String code}) {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> fetchMe() {
    throw UnimplementedError();
  }
}

class _FakeGoogleSignIn implements GoogleSignInGateway {
  @override
  Future<String?> getIdToken() async => 'fake-id-token';

  @override
  Future<void> signOut() async {}
}

void main() {
  test('sets_pending_verification_email_when_register_succeeds', () async {
    final service = _FakeAuthService();
    final controller = AuthController(authService: service);

    await controller.registerWithEmail(
      email: 'new@example.com',
      password: 'password123',
    );

    expect(controller.isLoggedIn, isFalse);
    expect(controller.pendingVerificationEmail, 'new@example.com');
    expect(controller.accessToken, isNull);
  });

  test('stores_session_when_six_digit_code_verifies', () async {
    final service = _FakeAuthService()
      ..nextToken = 'abc'
      ..nextUser = const AuthUser(
        id: '1',
        displayName: 'Verified',
        email: 'v@example.com',
        emailVerified: true,
      );
    final controller = AuthController(authService: service);
    controller.pendingVerificationEmail = 'v@example.com';

    await controller.verifyEmail(code: '123456');

    expect(controller.isLoggedIn, isTrue);
    expect(controller.currentUser?.email, 'v@example.com');
    expect(controller.accessToken, 'abc');
    expect(controller.pendingVerificationEmail, isNull);
  });

  test('stores_session_when_login_succeeds', () async {
    final service = _FakeAuthService()
      ..nextToken = 'login-token'
      ..nextUser = const AuthUser(
        id: '2',
        displayName: 'Reader',
        email: 'r@example.com',
        emailVerified: true,
      );
    final controller = AuthController(authService: service);

    await controller.signInWithEmail(email: 'r@example.com', password: 'password123');

    expect(controller.isLoggedIn, isTrue);
    expect(controller.currentUser?.email, 'r@example.com');
  });

  test('sets_pending_verification_when_login_returns_email_not_verified', () async {
    final service = _FakeAuthService()
      ..loginError = const EmailNotVerifiedException('pending@example.com');
    final controller = AuthController(authService: service);

    await controller.signInWithEmail(
      email: 'pending@example.com',
      password: 'password123',
    );

    expect(controller.isLoggedIn, isFalse);
    expect(controller.pendingVerificationEmail, 'pending@example.com');
  });

  test('stores_session_when_google_sign_in_succeeds', () async {
    final service = _FakeAuthService()
      ..nextUser = const AuthUser(
        id: 'g1',
        displayName: 'Google User',
        email: 'g@example.com',
        emailVerified: true,
      );
    final controller = AuthController(authService: service);

    await controller.signInWithGoogle();

    expect(controller.isLoggedIn, isTrue);
    expect(controller.currentUser?.email, 'g@example.com');
  });

  test('clears_session_when_signed_out', () async {
    final service = _FakeAuthService();
    final controller = AuthController(authService: service);
    await controller.signInWithGoogle();

    await controller.signOut();

    expect(controller.isLoggedIn, isFalse);
    expect(controller.currentUser, isNull);
    expect(controller.accessToken, isNull);
  });

  test('hydrates_user_when_restore_session_succeeds', () async {
    final service = _FakeAuthService()
      ..restoreResult = const AuthSession(
        accessToken: 'restored-token',
        user: AuthUser(
          id: '1',
          displayName: 'Restored',
          email: 'r@example.com',
          emailVerified: true,
        ),
      );
    final controller = AuthController(authService: service);

    await controller.restoreSession();

    expect(controller.isLoggedIn, isTrue);
    expect(controller.currentUser?.email, 'r@example.com');
    expect(controller.accessToken, 'restored-token');
  });

  test('clears_session_when_restore_session_returns_null', () async {
    final service = _FakeAuthService()..restoreResult = null;
    final controller = AuthController(authService: service)
      ..accessToken = 'stale'
      ..currentUser = const AuthUser(id: '1', displayName: 'Stale');

    await controller.restoreSession();

    expect(controller.isLoggedIn, isFalse);
    expect(controller.accessToken, isNull);
    expect(controller.currentUser, isNull);
  });

  test('maps_api_errors_to_user_facing_messages', () {
    final message = userFacingAuthError(
      ApiException(401, '{"detail":"Invalid email or password"}'),
    );
    expect(message, 'Invalid email or password.');
  });

  test('detects_email_not_verified_detail_from_json', () {
    expect(isEmailNotVerifiedDetail('{"detail":"email_not_verified"}'), isTrue);
    expect(isEmailNotVerifiedDetail('{"detail":"other"}'), isFalse);
  });
}
