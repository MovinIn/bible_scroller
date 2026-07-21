import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

class _FakeStorage extends StorageService {
  @override
  Future<String> readTranslationVersion({String fallback = 'esv'}) async => 'esv';

  @override
  Future<bool> readAutoplayVoice({bool fallback = true}) async => false;

  @override
  Future<bool> readVoiceMuted({bool fallback = false}) async => false;
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test');

  int wordStudyCalls = 0;

  @override
  Future<WordStudy> fetchWordStudy({
    required Reel reel,
    int? startVerse,
    int? endVerse,
  }) async {
    wordStudyCalls += 1;
    return const WordStudy(
      reference: 'Genesis 1:1',
      versionId: 'bsb',
      verses: [
        WordStudyVerse(
          verse: 1,
          groups: [
            WordGroup(
              phrase: 'In the beginning',
              strongs: 'H7225',
              lemma: 'רֵאשִׁית',
              definition: 'the first',
            ),
            WordGroup(
              phrase: 'God',
              strongs: 'H430',
              lemma: 'אֱלֹהִים',
              definition: 'gods',
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  final reel = Reel(
    id: 1,
    reference: 'Genesis 1:1',
    book: 'Genesis',
    chapter: 1,
    startVerse: 1,
    endVerse: 1,
    slug: 'g',
    imageUrl: 'https://example.com/a.png',
    iqBookId: '01',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );

  test('keeps translationVersion unchanged when define mode is enabled', () async {
    final api = _FakeApi();
    final controller = ReelsController(api: api, storage: _FakeStorage());
    controller.debugSeedFeed([reel]);
    expect(controller.translationVersion, 'esv');

    await controller.setDefineMode(true);

    expect(controller.defineModeEnabled, isTrue);
    expect(controller.translationVersion, 'esv');
    expect(api.wordStudyCalls, 1);
    expect(
      controller.wordStudyFor(reel)?.allGroups.first.phrase,
      'In the beginning',
    );
  });

  test('clears define overlay when define mode is disabled', () async {
    final controller = ReelsController(api: _FakeApi(), storage: _FakeStorage());
    controller.debugSeedFeed([reel]);
    await controller.setDefineMode(true);
    await controller.setDefineMode(false);

    expect(controller.defineModeEnabled, isFalse);
  });
}
