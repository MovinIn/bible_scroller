enum VoiceoverPresentation {
  /// Full section text (no clip playing / never started).
  sectionIdle,

  /// Clip playing; UI shows [activeVerseNumber] only.
  playingActiveVerse,

  /// Clip finished; fade in full section text.
  sectionReveal,
}
