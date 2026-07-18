import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/config/google_oauth_config.dart';

void main() {
  test('includes_android_and_ios_ids_in_server_audiences', () {
    expect(
      GoogleOAuthConfig.serverAudienceIds,
      contains(GoogleOAuthConfig.androidClientId),
    );
    expect(
      GoogleOAuthConfig.serverAudienceIds,
      contains(GoogleOAuthConfig.iosClientId),
    );
    expect(
      GoogleOAuthConfig.serverAudienceIds,
      contains(GoogleOAuthConfig.webClientId),
    );
  });
}
