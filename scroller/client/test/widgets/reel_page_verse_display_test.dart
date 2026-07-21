import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/utils/voiceover_presentation.dart';
import 'package:bible_scroller/widgets/reel_page.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final reel = Reel(
    id: 1,
    reference: 'John 3:16-17',
    book: 'John',
    chapter: 3,
    startVerse: 16,
    endVerse: 17,
    slug: 'j',
    imageUrl: 'https://example.com/a.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );

  Future<void> pumpPage(WidgetTester tester, ReelsController controller) async {
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
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows active verse text while playing clip', (tester) async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: _FakeStorage(),
    );
    controller.debugSeedVoiceover(
      reelId: reel.id,
      presentation: VoiceoverPresentation.playingActiveVerse,
      activeVerse: 16,
      sectionText: 'Full section.',
      perVerseText: {16: 'For God so loved the world.'},
    );

    await pumpPage(tester, controller);

    expect(find.text('For God so loved the world.'), findsOneWidget);
    expect(find.text('Full section.'), findsNothing);
  });

  testWidgets('shows full section text after clip reveal', (tester) async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: _FakeStorage(),
    );
    controller.debugSeedVoiceover(
      reelId: reel.id,
      presentation: VoiceoverPresentation.sectionReveal,
      activeVerse: null,
      sectionText: 'Full section text here.',
      perVerseText: {16: 'For God so loved the world.'},
    );

    await pumpPage(tester, controller);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Full section text here.'), findsOneWidget);
  });
}
