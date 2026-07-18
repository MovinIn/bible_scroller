class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    this.email,
    this.emailVerified = false,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? email;
  final bool emailVerified;
  final String? avatarUrl;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      email: json['email'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class RegisterResult {
  const RegisterResult._({required this.email, required this.verificationRequired});

  factory RegisterResult.verificationRequired(String email) {
    return RegisterResult._(email: email, verificationRequired: true);
  }

  final String email;
  final bool verificationRequired;
}

class EmailNotVerifiedException implements Exception {
  const EmailNotVerifiedException(this.email);

  final String email;

  @override
  String toString() => 'EmailNotVerifiedException($email)';
}

class SignInCancelledException implements Exception {
  const SignInCancelledException();

  @override
  String toString() => 'SignInCancelledException';
}
