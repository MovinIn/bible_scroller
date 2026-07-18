import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config/google_oauth_config.dart';
import '../models/auth_models.dart';
import 'api_client.dart';
import 'token_storage.dart';

abstract class AuthApi {
  String? accessToken;
  String get deviceId;

  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthSession> login({required String email, required String password});

  Future<AuthSession> verifyEmail({required String email, required String code});

  Future<void> resendVerification({required String email});

  Future<AuthSession> signInWithGoogleIdToken(String idToken);

  Future<AuthUser> fetchMe();
}

abstract class GoogleSignInGateway {
  Future<String?> getIdToken();
  Future<void> signOut();
}

class GoogleSignInAdapter implements GoogleSignInGateway {
  GoogleSignInAdapter({
    GoogleSignIn? googleSignIn,
    String iosClientId = GoogleOAuthConfig.iosClientId,
    String webClientId = GoogleOAuthConfig.webClientId,
  })  : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
        _iosClientId = iosClientId,
        _webClientId = webClientId;

  final GoogleSignIn _googleSignIn;
  final String _iosClientId;
  final String _webClientId;
  Future<void>? _initialized;

  Future<void> _ensureInitialized() {
    return _initialized ??= _googleSignIn.initialize(
      clientId: _platformClientId(),
      serverClientId: _webClientId.isNotEmpty ? _webClientId : null,
    );
  }

  String? _platformClientId() {
    if (kIsWeb) {
      return _webClientId.isNotEmpty ? _webClientId : null;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _iosClientId;
      default:
        return null;
    }
  }

  @override
  Future<String?> getIdToken() async {
    await _ensureInitialized();
    try {
      final account = await _googleSignIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (err) {
      if (err.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
  }
}

bool isEmailNotVerifiedDetail(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) {
      return json['detail'] == 'email_not_verified';
    }
  } catch (_) {
    // Fall through.
  }
  return false;
}

String userFacingAuthError(Object err) {
  if (err is ApiException) {
    try {
      final json = jsonDecode(err.body);
      if (json is Map<String, dynamic> && json['detail'] is String) {
        final detail = json['detail'] as String;
        if (detail == 'email_not_verified') {
          return 'Please verify your email first.';
        }
        if (err.statusCode == 429) {
          return 'Too many attempts. Please try again later.';
        }
        if (err.statusCode == 401) {
          return 'Invalid email or password.';
        }
        if (err.statusCode == 400) {
          return 'Invalid or expired verification code.';
        }
        return detail;
      }
    } catch (_) {
      // Fall through.
    }
    if (err.statusCode == 429) {
      return 'Too many attempts. Please try again later.';
    }
    if (err.statusCode == 401) {
      return 'Invalid email or password.';
    }
    return 'Something went wrong. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

class AuthService {
  AuthService({
    required AuthApi api,
    required TokenStorage storage,
    required GoogleSignInGateway googleSignIn,
  })  : _api = api,
        storage = storage,
        _googleSignIn = googleSignIn;

  final AuthApi _api;
  final TokenStorage storage;
  final GoogleSignInGateway _googleSignIn;

  Future<RegisterResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _api.register(email: email, password: password, displayName: displayName);
  }

  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final session = await _api.login(email: email, password: password);
      await storage.saveToken(session.accessToken);
      _api.accessToken = session.accessToken;
      return session;
    } on ApiException catch (err) {
      if (err.statusCode == 403 && isEmailNotVerifiedDetail(err.body)) {
        throw EmailNotVerifiedException(email);
      }
      rethrow;
    }
  }

  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async {
    final session = await _api.verifyEmail(email: email, code: code);
    await storage.saveToken(session.accessToken);
    _api.accessToken = session.accessToken;
    return session;
  }

  Future<void> resendVerification(String email) {
    return _api.resendVerification(email: email);
  }

  Future<AuthSession> signInWithGoogle() async {
    final idToken = await _googleSignIn.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const SignInCancelledException();
    }
    final session = await _api.signInWithGoogleIdToken(idToken);
    await storage.saveToken(session.accessToken);
    _api.accessToken = session.accessToken;
    return session;
  }

  Future<AuthSession?> restoreSession() async {
    final token = await storage.readToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    _api.accessToken = token;
    try {
      final user = await _api.fetchMe();
      return AuthSession(accessToken: token, user: user);
    } on ApiException catch (err) {
      if (err.statusCode == 401 || err.statusCode == 403) {
        await storage.clearToken();
        _api.accessToken = null;
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await storage.clearToken();
    _api.accessToken = null;
    await _googleSignIn.signOut();
  }
}

/// HTTP auth endpoints wired through [ApiClient]'s base URL / device id.
class ApiAuthClient implements AuthApi {
  ApiAuthClient({
    required this.apiClient,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final ApiClient apiClient;
  final http.Client _http;

  @override
  String? get accessToken => apiClient.accessToken;

  @override
  set accessToken(String? value) => apiClient.accessToken = value;

  @override
  String get deviceId => apiClient.deviceId;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Device-Id': deviceId,
    };
    final token = accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path) => Uri.parse('${apiClient.baseUrl}$path');

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _http.post(
      _uri('/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        if (displayName != null) 'display_name': displayName,
      }),
    );
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return RegisterResult.verificationRequired(json['email'] as String);
  }

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    final response = await _http.post(
      _uri('/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
    return AuthSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<AuthSession> verifyEmail({required String email, required String code}) async {
    final response = await _http.post(
      _uri('/auth/verify-email'),
      headers: _headers,
      body: jsonEncode({'email': email, 'code': code}),
    );
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
    return AuthSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> resendVerification({required String email}) async {
    final response = await _http.post(
      _uri('/auth/resend-verification'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  @override
  Future<AuthSession> signInWithGoogleIdToken(String idToken) async {
    final response = await _http.post(
      _uri('/auth/google'),
      headers: _headers,
      body: jsonEncode({'id_token': idToken}),
    );
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
    return AuthSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<AuthUser> fetchMe() async {
    final response = await _http.get(_uri('/users/me'), headers: _headers);
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
    return AuthUser.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
