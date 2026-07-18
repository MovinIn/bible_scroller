import 'position_cookie_stub.dart'
    if (dart.library.html) 'position_cookie_web.dart' as impl;

export 'position_cookie_codec.dart';

void writeLastReelCookie(int reelId) => impl.writeLastReelCookie(reelId);

void clearLastReelCookie() => impl.clearLastReelCookie();

int? readLastReelIdFromCookie() => impl.readLastReelIdFromCookie();
