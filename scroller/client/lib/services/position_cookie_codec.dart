/// Pure cookie string helpers (testable without dart:html).
const String kLastReelCookieName = 'bscroller_last_reel_id';
const int kLastReelCookieMaxAgeSeconds = 365 * 24 * 60 * 60;

String buildLastReelCookieValue(int reelId) {
  return '$kLastReelCookieName=$reelId; Path=/; Max-Age=$kLastReelCookieMaxAgeSeconds; SameSite=Lax';
}

String buildClearedLastReelCookieValue() {
  return '$kLastReelCookieName=; Path=/; Max-Age=0; SameSite=Lax';
}

int? parseLastReelIdFromCookieHeader(String cookieHeader) {
  if (cookieHeader.trim().isEmpty) {
    return null;
  }
  for (final part in cookieHeader.split(';')) {
    final pair = part.trim();
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final name = pair.substring(0, eq).trim();
    final value = pair.substring(eq + 1).trim();
    if (name == kLastReelCookieName) {
      return int.tryParse(value);
    }
  }
  return null;
}
