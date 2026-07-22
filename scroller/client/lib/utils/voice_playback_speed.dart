String formatVoicePlaybackSpeed(double speed) {
  final value = (speed * 4).round() / 4;
  if (value == value.truncateToDouble()) {
    return '${value.toInt()}x';
  }
  return '${value}x';
}
