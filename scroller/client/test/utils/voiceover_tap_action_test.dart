import 'package:bible_scroller/utils/voiceover_tap_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns pause when current reel audio is playing', () {
    expect(
      resolveVoiceoverTapAction(
        isCurrentReelLoaded: true,
        playing: true,
        completed: false,
      ),
      VoiceoverTapAction.pause,
    );
  });

  test('returns resume when current reel audio is paused mid playback', () {
    expect(
      resolveVoiceoverTapAction(
        isCurrentReelLoaded: true,
        playing: false,
        completed: false,
      ),
      VoiceoverTapAction.resume,
    );
  });

  test('returns replay when current reel audio has finished', () {
    expect(
      resolveVoiceoverTapAction(
        isCurrentReelLoaded: true,
        playing: false,
        completed: true,
      ),
      VoiceoverTapAction.replay,
    );
  });

  test('returns start when no audio is loaded for the reel', () {
    expect(
      resolveVoiceoverTapAction(
        isCurrentReelLoaded: false,
        playing: false,
        completed: false,
      ),
      VoiceoverTapAction.start,
    );
  });

  test('returns start when a different reel is loaded', () {
    expect(
      resolveVoiceoverTapAction(
        isCurrentReelLoaded: false,
        playing: true,
        completed: false,
      ),
      VoiceoverTapAction.start,
    );
  });
}
