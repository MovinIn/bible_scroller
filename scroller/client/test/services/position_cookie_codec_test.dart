import 'package:bible_scroller/services/position_cookie_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds cookie with reel id path max-age and samesite when reel is saved', () {
    final cookie = buildLastReelCookieValue(42);

    expect(cookie, contains('bscroller_last_reel_id=42'));
    expect(cookie, contains('Path=/'));
    expect(cookie, contains('Max-Age=31536000'));
    expect(cookie, contains('SameSite=Lax'));
  });

  test('returns reel id when cookie header contains last reel cookie', () {
    const header = 'other=1; bscroller_last_reel_id=17; theme=dark';

    expect(parseLastReelIdFromCookieHeader(header), 17);
  });

  test('returns null when last reel cookie is missing', () {
    expect(parseLastReelIdFromCookieHeader('theme=dark; other=1'), isNull);
  });

  test('returns null when last reel cookie value is not an integer', () {
    expect(parseLastReelIdFromCookieHeader('bscroller_last_reel_id=abc'), isNull);
  });

  test('builds cleared cookie with zero max-age when position is reset', () {
    final cookie = buildClearedLastReelCookieValue();

    expect(cookie, contains('bscroller_last_reel_id='));
    expect(cookie, contains('Max-Age=0'));
  });
}
