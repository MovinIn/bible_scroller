import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/utils/voice_playback_speed.dart';

void main() {
  test('formats whole-number speeds without decimals', () {
    expect(formatVoicePlaybackSpeed(1.0), '1x');
    expect(formatVoicePlaybackSpeed(2.0), '2x');
  });

  test('formats quarter-step speeds with one decimal when needed', () {
    expect(formatVoicePlaybackSpeed(0.5), '0.5x');
    expect(formatVoicePlaybackSpeed(1.5), '1.5x');
    expect(formatVoicePlaybackSpeed(1.25), '1.25x');
  });
}
