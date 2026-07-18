import 'package:bible_scroller/utils/verse_cache_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns false for placeholder verse text that mentions missing api key', () {
    expect(
      shouldCacheVerseText(
        '[John 3:16 placeholder — set BIBLE_BRAIN_API_KEY]',
      ),
      isFalse,
    );
  });

  test('returns true for real verse text', () {
    expect(
      shouldCacheVerseText('For God so loved the world'),
      isTrue,
    );
  });

  test('returns false for example.com audio urls', () {
    expect(
      isPlayableAudioUrl('https://example.com/audio/JHN/3/niv.mp3'),
      isFalse,
    );
  });

  test('returns true for real https audio urls', () {
    expect(
      isPlayableAudioUrl(
        'https://audio.bible.helloao.org/api/BSB/JHN/3/audio/david.mp3',
      ),
      isTrue,
    );
  });

  test('returns false for empty audio urls', () {
    expect(isPlayableAudioUrl(''), isFalse);
  });
}
