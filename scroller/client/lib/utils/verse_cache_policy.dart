bool shouldCacheVerseText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return !trimmed.contains('BIBLE_BRAIN_API_KEY');
}

bool isPlayableAudioUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  if (uri.host == 'example.com' || uri.host.endsWith('.example.com')) {
    return false;
  }
  // just_audio on web cannot play HLS playlists from Bible Brain streams.
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8') || path.contains('playlist.m3u8')) {
    return false;
  }
  return true;
}
