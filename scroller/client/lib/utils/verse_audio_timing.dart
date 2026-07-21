import '../models/models.dart';

/// Active verse number for [positionMs], or null if outside the timed section.
int? activeVerseAtPositionMs(
  List<BibleAudioVerseTiming> verses,
  int positionMs,
) {
  if (verses.isEmpty) {
    return null;
  }
  BibleAudioVerseTiming? active;
  for (final verse in verses) {
    if (positionMs >= verse.startMs && positionMs < verse.endMs) {
      return verse.verse;
    }
    if (positionMs >= verse.startMs) {
      active = verse;
    }
  }
  // At exact section end, treat as last verse until clip-finished handler runs.
  if (active != null && positionMs >= active.startMs) {
    return active.verse;
  }
  return null;
}

int? sectionStartMs(List<BibleAudioVerseTiming> verses) {
  if (verses.isEmpty) {
    return null;
  }
  return verses.first.startMs;
}

int? sectionEndMs(List<BibleAudioVerseTiming> verses) {
  if (verses.isEmpty) {
    return null;
  }
  return verses.last.endMs;
}

bool isVerseClipFinished(List<BibleAudioVerseTiming> verses, int positionMs) {
  final end = sectionEndMs(verses);
  if (end == null) {
    return true;
  }
  return positionMs >= end;
}

/// Bible Brain sentinel: [endMs] == -1 means "play until chapter audio ends".
const int openEndedVerseEndMs = -1;

List<BibleAudioVerseTiming> clampOpenEndedVerseTimings(
  List<BibleAudioVerseTiming> verses,
  int? audioDurationMs,
) {
  if (verses.isEmpty || audioDurationMs == null || audioDurationMs <= 0) {
    return verses;
  }
  return [
    for (final verse in verses)
      if (verse.endMs == openEndedVerseEndMs || verse.endMs > audioDurationMs)
        BibleAudioVerseTiming(
          verse: verse.verse,
          startMs: verse.startMs,
          endMs: audioDurationMs,
        )
      else
        verse,
  ];
}
