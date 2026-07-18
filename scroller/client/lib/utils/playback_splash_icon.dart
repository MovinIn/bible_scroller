import 'voiceover_tap_action.dart';

enum PlaybackSplashIcon { play, pause }

PlaybackSplashIcon playbackSplashIconFor(VoiceoverTapAction action) {
  if (action == VoiceoverTapAction.pause) {
    return PlaybackSplashIcon.pause;
  }
  return PlaybackSplashIcon.play;
}
