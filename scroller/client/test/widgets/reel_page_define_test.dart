import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/widgets/reel_page.dart';
import 'package:bible_scroller/widgets/word_definition_sheet.dart';

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

  @override
  Future<WordStudy> fetchWordStudy({
    required Reel reel,
    int? startVerse,
    int? endVerse,
  }) async {
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
              definition: 'the first, in place, time, order or rank',
            ),
            WordGroup(
              phrase: 'God',
              strongs: 'H430',
              lemma: 'אֱלֹהִים',
              definition: 'gods in the ordinary sense',
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<ReelsController> pumpPage(WidgetTester tester) async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: _FakeStorage(),
    );
    controller.debugSeedFeed([reel]);
    controller.debugSeedVoiceover(
      reelId: reel.id,
      presentation: controller.voiceoverPresentation,
      sectionText: 'In the beginning God created the heavens and the earth.',
    );
    await controller.setDefineMode(true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: ReelPage(
              reel: reel,
              controller: controller,
              onCommentsTap: () {},
              onTranslationTap: () {},
              onVoiceTap: () {},
              onDefineTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('shows BSB grouped phrases when define mode is on', (tester) async {
    await pumpPage(tester);

    expect(find.text('In the beginning'), findsOneWidget);
    expect(find.text('God'), findsOneWidget);
    expect(
      find.text('In the beginning God created the heavens and the earth.'),
      findsNothing,
    );
  });

  testWidgets('shows definition popup when a word group is tapped', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('God'));
    await tester.pumpAndSettle();

    expect(find.byType(WordDefinitionSheet), findsOneWidget);
    expect(find.text('אֱלֹהִים'), findsOneWidget);
    expect(find.text('H430'), findsOneWidget);
    expect(find.text('gods in the ordinary sense'), findsOneWidget);
  });

  testWidgets('restores translation text when define mode is off', (tester) async {
    final controller = await pumpPage(tester);
    await controller.setDefineMode(false);
    await tester.pump();

    expect(
      find.text('In the beginning God created the heavens and the earth.'),
      findsOneWidget,
    );
  });
}
