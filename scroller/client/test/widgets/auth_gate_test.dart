import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bible_scroller/models/auth_models.dart';
import 'package:bible_scroller/services/auth_service.dart';
import 'package:bible_scroller/services/token_storage.dart';
import 'package:bible_scroller/state/auth_controller.dart';
import 'package:bible_scroller/widgets/auth_gate.dart';

class _LoggedInService extends AuthService {
  _LoggedInService()
      : super(
          api: _NoopApi(),
          storage: InMemoryTokenStorage(),
          googleSignIn: _NoopGoogle(),
        );
}

class _NoopApi implements AuthApi {
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
  testWidgets('returns_true_immediately_when_already_logged_in', (tester) async {
    final controller = AuthController(authService: _LoggedInService())
      ..accessToken = 'tok'
      ..currentUser = const AuthUser(
        id: '1',
        displayName: 'User',
        email: 'u@example.com',
        emailVerified: true,
      );

    late bool result;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await ensureLoggedIn(context);
                  },
                  child: const Text('Go'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(result, isTrue);
    expect(find.byKey(const Key('auth_email_field')), findsNothing);
  });
}
