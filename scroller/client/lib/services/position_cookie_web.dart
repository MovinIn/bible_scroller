// Web-only implementation selected via conditional import.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'position_cookie_codec.dart';

void writeLastReelCookie(int reelId) {
  html.document.cookie = buildLastReelCookieValue(reelId);
}

void clearLastReelCookie() {
  html.document.cookie = buildClearedLastReelCookieValue();
}

int? readLastReelIdFromCookie() {
  return parseLastReelIdFromCookieHeader(html.document.cookie ?? '');
}
