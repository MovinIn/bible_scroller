import 'package:bible_scroller/utils/playback_splash_icon.dart';
import 'package:bible_scroller/utils/voiceover_tap_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns pause icon when voiceover tap action is pause', () {
    expect(
      playbackSplashIconFor(VoiceoverTapAction.pause),
      PlaybackSplashIcon.pause,
    );
  });

  test('returns play icon when voiceover tap action is resume', () {
    expect(
      playbackSplashIconFor(VoiceoverTapAction.resume),
      PlaybackSplashIcon.play,
    );
  });

  test('returns play icon when voiceover tap action is replay', () {
    expect(
      playbackSplashIconFor(VoiceoverTapAction.replay),
      PlaybackSplashIcon.play,
    );
  });

  test('returns play icon when voiceover tap action is start', () {
    expect(
      playbackSplashIconFor(VoiceoverTapAction.start),
      PlaybackSplashIcon.play,
    );
  });
}
