import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bible_scroller/models/auth_models.dart';
import 'package:bible_scroller/services/auth_service.dart';
import 'package:bible_scroller/services/token_storage.dart';
import 'package:bible_scroller/state/auth_controller.dart';
import 'package:bible_scroller/widgets/auth_sheet.dart';

class _SheetFakeAuthService extends AuthService {
  _SheetFakeAuthService()
      : super(
          api: _StubApi(),
          storage: InMemoryTokenStorage(),
          googleSignIn: _StubGoogle(),
        );

  bool verifySucceeds = true;

  @override
  Future<RegisterResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return RegisterResult.verificationRequired(email);
  }

  @override
  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async {
    if (!verifySucceeds) {
      throw Exception('bad code');
    }
    final session = AuthSession(
      accessToken: 'tok',
      user: AuthUser(
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
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> resendVerification(String email) async {}
}

class _StubApi implements AuthApi {
  @override
  String? accessToken;

  @override
  String get deviceId => 'd';

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

  @override
  Future<AuthUser> fetchMe() => throw UnimplementedError();
}

class _StubGoogle implements GoogleSignInGateway {
  @override
  Future<String?> getIdToken() async => null;

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('shows_create_account_title_when_sheet_opens', (tester) async {
    final controller = AuthController(authService: _SheetFakeAuthService());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: AuthSheet()),
        ),
      ),
    );

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Have an account? Sign in'), findsOneWidget);
    expect(find.byKey(const Key('auth_email_field')), findsOneWidget);
    expect(find.byKey(const Key('auth_google_button')), findsOneWidget);
  });

  testWidgets('shows_sign_in_title_when_user_taps_have_an_account', (tester) async {
    final controller = AuthController(authService: _SheetFakeAuthService());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: AuthSheet()),
        ),
      ),
    );

    await tester.tap(find.text('Have an account? Sign in'));
    await tester.pump();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('shows_six_digit_code_field_when_register_requires_verification', (tester) async {
    final controller = AuthController(authService: _SheetFakeAuthService());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: AuthSheet()),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('auth_email_field')), 'new@example.com');
    await tester.enterText(find.byKey(const Key('auth_password_field')), 'password123');
    await tester.tap(find.byKey(const Key('auth_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth_code_field')), findsOneWidget);
    expect(find.byKey(const Key('auth_verify_button')), findsOneWidget);
    expect(find.byKey(const Key('auth_resend_button')), findsOneWidget);
    expect(find.byKey(const Key('auth_back_to_sign_in_button')), findsOneWidget);
    expect(find.textContaining('Check your email'), findsOneWidget);
  });

  testWidgets('returns_to_sign_in_when_back_to_sign_in_is_tapped', (tester) async {
    final controller = AuthController(authService: _SheetFakeAuthService());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: AuthSheet()),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('auth_email_field')), 'new@example.com');
    await tester.enterText(find.byKey(const Key('auth_password_field')), 'password123');
    await tester.tap(find.byKey(const Key('auth_submit_button')));
    await tester.pumpAndSettle();

    expect(controller.pendingVerificationEmail, 'new@example.com');

    await tester.tap(find.byKey(const Key('auth_back_to_sign_in_button')));
    await tester.pumpAndSettle();

    expect(controller.pendingVerificationEmail, isNull);
    expect(find.byKey(const Key('auth_code_field')), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(const Key('auth_email_field')), findsOneWidget);
  });

  testWidgets('signs_user_in_automatically_when_verification_code_is_correct', (tester) async {
    final controller = AuthController(authService: _SheetFakeAuthService());
    var successCalls = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: AuthSheet(onSuccess: () => successCalls += 1),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('auth_email_field')), 'new@example.com');
    await tester.enterText(find.byKey(const Key('auth_password_field')), 'password123');
    await tester.tap(find.byKey(const Key('auth_submit_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('auth_code_field')), '123456');
    await tester.tap(find.byKey(const Key('auth_verify_button')));
    await tester.pumpAndSettle();

    expect(controller.isLoggedIn, isTrue);
    expect(controller.accessToken, 'tok');
    expect(controller.currentUser?.email, 'new@example.com');
    expect(controller.pendingVerificationEmail, isNull);
    expect(successCalls, 1);
  });
}
