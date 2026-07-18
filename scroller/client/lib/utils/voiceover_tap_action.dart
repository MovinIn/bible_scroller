enum VoiceoverTapAction { pause, resume, replay, start }

/// Decides what a reel-body tap should do to voiceover playback.
VoiceoverTapAction resolveVoiceoverTapAction({
  required bool isCurrentReelLoaded,
  required bool playing,
  required bool completed,
}) {
  if (!isCurrentReelLoaded) {
    return VoiceoverTapAction.start;
  }
  if (playing) {
    return VoiceoverTapAction.pause;
  }
  if (completed) {
    return VoiceoverTapAction.replay;
  }
  return VoiceoverTapAction.resume;
}
