/// Google OAuth client IDs for Sign-In (public; safe to embed in the app).
///
/// Override at build time with `--dart-define=GOOGLE_WEB_CLIENT_ID=...` once
/// the Web application client ID is known (ends in `.apps.googleusercontent.com`,
/// not `GOCSPX-...`).
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  static const androidClientId =
      '315895045315-5rtkbs5sve6c3jac9c8hh9m2i58gvrq7.apps.googleusercontent.com';

  static const iosClientId =
      '315895045315-e90fn22s1q3dghmc6u7neqae3668lqnc.apps.googleusercontent.com';

  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '315895045315-54809ltm3mnp79qurdl7512c55mvbveo.apps.googleusercontent.com',
  );

  /// iOS reversed client ID for `CFBundleURLSchemes` / Google redirect handling.
  static const iosUrlScheme =
      'com.googleusercontent.apps.315895045315-e90fn22s1q3dghmc6u7neqae3668lqnc';

  /// Comma-separated audiences for server-side ID token verification.
  static String get serverAudienceIds {
    return [
      if (webClientId.isNotEmpty) webClientId,
      androidClientId,
      iosClientId,
    ].join(',');
  }
}
