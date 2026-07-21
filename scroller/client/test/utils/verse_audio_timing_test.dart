import 'package:flutter_test/flutter_test.dart';
import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/utils/verse_audio_timing.dart';

void main() {
  const verses = [
    BibleAudioVerseTiming(verse: 16, startMs: 45200, endMs: 52100),
    BibleAudioVerseTiming(verse: 17, startMs: 52100, endMs: 59800),
  ];

  test('returns first verse when position is at section start', () {
    expect(activeVerseAtPositionMs(verses, 45200), 16);
  });

  test('returns second verse when position crosses next start', () {
    expect(activeVerseAtPositionMs(verses, 52100), 17);
  });

  test('returns null when position is before section', () {
    expect(activeVerseAtPositionMs(verses, 40000), isNull);
  });

  test('returns null when timings are empty', () {
    expect(activeVerseAtPositionMs(const [], 45200), isNull);
  });

  test('returns section start and end ms from timings', () {
    expect(sectionStartMs(verses), 45200);
    expect(sectionEndMs(verses), 59800);
  });

  test('returns null section bounds when timings are empty', () {
    expect(sectionStartMs(const []), isNull);
    expect(sectionEndMs(const []), isNull);
  });

  test('reports clip finished when position reaches section end', () {
    expect(isVerseClipFinished(verses, 59800), isTrue);
    expect(isVerseClipFinished(verses, 59799), isFalse);
  });

  test('clamps open-ended last verse to audio duration', () {
    const openEnded = [
      BibleAudioVerseTiming(verse: 17, startMs: 52100, endMs: openEndedVerseEndMs),
    ];
    expect(
      clampOpenEndedVerseTimings(openEnded, 90000),
      [
        const BibleAudioVerseTiming(verse: 17, startMs: 52100, endMs: 90000),
      ],
    );
  });
}
