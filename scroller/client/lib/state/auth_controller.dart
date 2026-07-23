import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({required AuthService authService}) : _authService = authService;

  final AuthService _authService;

  AuthUser? currentUser;
  String? accessToken;
  String? pendingVerificationEmail;
  String? error;
  bool busy = false;

  bool get isLoggedIn => accessToken != null && currentUser != null;

  void setError(String message) {
    error = message;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    try {
      final session = await _authService.restoreSession();
      if (session == null) {
        currentUser = null;
        accessToken = null;
      } else {
        _applySession(session);
      }
    } catch (_) {
      currentUser = null;
      accessToken = null;
    }
    notifyListeners();
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await _authService.registerWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      pendingVerificationEmail = result.email;
    } catch (err) {
      error = userFacingAuthError(err);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = await _authService.signInWithEmail(email: email, password: password);
      _applySession(session);
      pendingVerificationEmail = null;
    } on EmailNotVerifiedException catch (err) {
      pendingVerificationEmail = err.email;
      currentUser = null;
      accessToken = null;
    } catch (err) {
      error = userFacingAuthError(err);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> verifyEmail({required String code}) async {
    final email = pendingVerificationEmail;
    if (email == null) {
      error = 'Enter the email you registered with first.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = await _authService.verifyEmail(email: email, code: code);
      _applySession(session);
      pendingVerificationEmail = null;
    } catch (err) {
      error = userFacingAuthError(err);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> resendVerification() async {
    final email = pendingVerificationEmail;
    if (email == null) {
      error = 'No verification email pending.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _authService.resendVerification(email);
    } catch (err) {
      error = userFacingAuthError(err);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = await _authService.signInWithGoogle();
      _applySession(session);
      pendingVerificationEmail = null;
    } on SignInCancelledException {
      // User dismissed the Google sheet — not an error.
    } catch (err) {
      error = userFacingAuthError(err);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    currentUser = null;
    accessToken = null;
    pendingVerificationEmail = null;
    error = null;
    notifyListeners();
  }

  void clearPendingVerification() {
    pendingVerificationEmail = null;
    error = null;
    notifyListeners();
  }

  void _applySession(AuthSession session) {
    currentUser = session.user;
    accessToken = session.accessToken;
  }
}
