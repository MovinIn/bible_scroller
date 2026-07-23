import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/screens/reels_feed_screen.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/utils/app_scroll_behavior.dart';
import 'package:bible_scroller/utils/page_wheel_navigator.dart';
import 'package:bible_scroller/utils/voiceover_tap_action.dart';

Reel _reel({required int id, required int chapter, required int verse}) {
  return Reel(
    id: id,
    reference: 'John $chapter:$verse',
    book: 'John',
    chapter: chapter,
    startVerse: verse,
    endVerse: verse,
    slug: 'John_${chapter}_$verse-$verse',
    imageUrl: 'https://example.com/$id.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _FakeApi extends ApiClient {
  _FakeApi(this.reels) : super(deviceId: 'test-device');

  final List<Reel> reels;

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    return ReelFeed(items: reels, nextCursor: null);
  }

  @override
  Future<ReelFeed> fetchDiscoveryReels({
    int limit = 10,
    List<int> excludeIds = const [],
  }) async {
    return ReelFeed(
      items: reels.reversed.toList(),
      nextCursor: null,
      prevCursor: null,
    );
  }

  @override
  Future<List<String>> fetchBooks() async => const ['Genesis', 'John', 'Acts'];

  @override
  Future<List<int>> fetchChapters(String book) async => const [1, 2, 3];

  @override
  Future<List<VerseSection>> fetchSections({
    required String book,
    required int chapter,
  }) async {
    return const [
      VerseSection(
        id: 1,
        startVerse: 16,
        endVerse: 16,
        reference: 'John 3:16',
      ),
    ];
  }

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    return const [
      BibleVersion(versionId: 'niv', name: 'New International Version'),
    ];
  }

  @override
  Future<BibleVerse> fetchVerse({
    required Reel reel,
    required String versionId,
    int? startVerse,
    int? endVerse,
  }) async {
    return BibleVerse(
      reference: reel.reference,
      versionId: versionId,
      text: 'Verse text for ${reel.reference}',
    );
  }

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    return BibleAudio(
      reference: reel.reference,
      versionId: versionId,
      audioUrl: '',
    );
  }
}

/// In-memory storage: widget tests run in FakeAsync, so real Hive /
/// SharedPreferences I/O would never complete.
class _FakeStorage extends StorageService {
  final Map<String, String> _verseCache = {};

  @override
  Future<String?> readDeviceId() async => 'test-device';

  @override
  Future<void> saveDeviceId(String deviceId) async {}

  @override
  Future<String> readTranslationVersion({String fallback = 'niv'}) async =>
      fallback;

  @override
  Future<void> saveTranslationVersion(String versionId) async {}

  @override
  Future<bool> readAutoplayVoice({bool fallback = true}) async => false;

  @override
  Future<void> saveAutoplayVoice(bool enabled) async {}

  @override
  Future<bool> readVoiceMuted({bool fallback = false}) async => fallback;

  @override
  Future<void> saveVoiceMuted(bool muted) async {}

  bool discoveryMode = false;

  @override
  Future<bool> readDiscoveryMode({bool fallback = false}) async => discoveryMode;

  @override
  Future<void> saveDiscoveryMode(bool enabled) async {
    discoveryMode = enabled;
  }

  @override
  Future<double> readVoicePlaybackSpeed({
    double fallback = StorageService.defaultVoicePlaybackSpeed,
  }) async =>
      fallback;

  @override
  Future<void> saveVoicePlaybackSpeed(double speed) async {}

  @override
  Future<void> rememberLikedReel(int reelId) async {}

  @override
  Future<void> forgetLikedReel(int reelId) async {}

  @override
  Future<bool> isReelCachedAsLiked(int reelId) async => false;

  @override
  Future<void> cacheVerseText({
    required int reelId,
    required String versionId,
    required String text,
  }) async {
    _verseCache['$reelId:$versionId'] = text;
  }

  @override
  Future<String?> readCachedVerseText({
    required int reelId,
    required String versionId,
  }) async {
    return _verseCache['$reelId:$versionId'];
  }
}

/// Records voiceover toggles so tests can assert body taps reach the
/// controller through the feed's outer drag GestureDetector.
class _SpyReelsController extends ReelsController {
  _SpyReelsController({required super.api, required super.storage});

  int voiceoverToggleCount = 0;
  VoiceoverTapAction nextToggleAction = VoiceoverTapAction.pause;
  VoiceoverTapAction peekAction = VoiceoverTapAction.pause;
  bool throwOnToggle = false;

  @override
  VoiceoverTapAction peekVoiceoverTapAction(Reel reel) => peekAction;

  @override
  Future<VoiceoverTapAction> toggleVoiceoverPlayback(Reel reel) async {
    voiceoverToggleCount += 1;
    if (throwOnToggle) {
      throw StateError('Audio unavailable');
    }
    return nextToggleAction;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpyReelsController controller;

  setUp(() {
    controller = _SpyReelsController(
      api: _FakeApi([
        _reel(id: 1, chapter: 3, verse: 16),
        _reel(id: 2, chapter: 1, verse: 1),
      ]),
      storage: _FakeStorage(),
    );
  });

  // Bounded pumps instead of pumpAndSettle: the reel background image
  // placeholder / progress indicator can animate indefinitely in tests.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFeed(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ReelsController>.value(
        value: controller,
        child: MaterialApp(
          scrollBehavior: AppScrollBehavior(),
          home: ReelsFeedScreen(
            wheelNavigator: PageWheelNavigator(cooldown: Duration.zero),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  double currentPage(WidgetTester tester) {
    final pageView = tester.widget<PageView>(find.byType(PageView));
    return pageView.controller!.page!;
  }

  Future<void> sendWheel(WidgetTester tester, double deltaDy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(PageView)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, deltaDy)));
    await settle(tester);
  }

  testWidgets('advances to next page when one wheel notch scrolls down',
      (tester) async {
    await pumpFeed(tester);
    expect(currentPage(tester), 0);

    // One small wheel notch, far less than a full viewport.
    await sendWheel(tester, 40);

    expect(currentPage(tester), 1);
  });

  testWidgets('returns to previous page when wheel scrolls up on second page',
      (tester) async {
    await pumpFeed(tester);
    await sendWheel(tester, 40);
    expect(currentPage(tester), 1);

    await sendWheel(tester, -40);

    expect(currentPage(tester), 0);
  });

  testWidgets('notifies controller of visible reel when wheel changes page',
      (tester) async {
    await pumpFeed(tester);
    expect(controller.currentIndex, 0);

    await sendWheel(tester, 40);

    expect(controller.currentIndex, 1);
  });

  testWidgets('stays on last page when wheel scrolls down at end of feed',
      (tester) async {
    await pumpFeed(tester);
    await sendWheel(tester, 40);
    expect(currentPage(tester), 1);

    await sendWheel(tester, 40);

    expect(currentPage(tester), 1);
  });

  testWidgets('advances to next page when reel body is dragged upward',
      (tester) async {
    await pumpFeed(tester);
    expect(currentPage(tester), 0);

    await tester.drag(
      find.byKey(const Key('reel_body_tap_target')).first,
      const Offset(0, -400),
    );
    await settle(tester);

    expect(currentPage(tester), 1);
  });

  testWidgets('returns to previous page when reel body is dragged downward',
      (tester) async {
    await pumpFeed(tester);
    await sendWheel(tester, 40);
    expect(currentPage(tester), 1);

    await tester.drag(
      find.byKey(const Key('reel_body_tap_target')).first,
      const Offset(0, 400),
    );
    await settle(tester);

    expect(currentPage(tester), 0);
  });

  testWidgets('stays on first page when reel body is dragged downward at start',
      (tester) async {
    await pumpFeed(tester);
    expect(currentPage(tester), 0);

    await tester.drag(
      find.byKey(const Key('reel_body_tap_target')).first,
      const Offset(0, 400),
    );
    await settle(tester);

    expect(currentPage(tester), 0);
  });

  testWidgets('toggles voiceover when reel body is tapped', (tester) async {
    await pumpFeed(tester);
    expect(controller.voiceoverToggleCount, 0);

    await tester.tapAt(const Offset(120, 300));
    await settle(tester);

    expect(controller.voiceoverToggleCount, 1);
  });

  testWidgets('shows pause splash overlay when reel body tap pauses audio',
      (tester) async {
    controller.nextToggleAction = VoiceoverTapAction.pause;
    controller.peekAction = VoiceoverTapAction.pause;
    await pumpFeed(tester);

    await tester.tapAt(const Offset(120, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.textContaining('Playing'), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  });

  testWidgets('shows play splash when body tap fails to start audio',
      (tester) async {
    controller.throwOnToggle = true;
    controller.peekAction = VoiceoverTapAction.start;
    await pumpFeed(tester);

    await tester.tapAt(const Offset(120, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(controller.voiceoverToggleCount, 1);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  });

  testWidgets('shows full book catalog in picker after lazy books load',
      (tester) async {
    await pumpFeed(tester);
    expect(controller.books, isEmpty);

    await tester.tap(find.byKey(const Key('book_picker_button')));
    await settle(tester);

    expect(controller.books, ['Genesis', 'John', 'Acts']);
    expect(find.text('Choose book'), findsOneWidget);
    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('Acts'), findsOneWidget);
  });

  testWidgets(
    'uses Material shuffle icon with MaterialIcons font when discovery is off',
    (tester) async {
      await pumpFeed(tester);

      expect(find.byKey(const Key('discovery_mode_toggle')), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.shuffle));
      expect(icon.icon, Icons.shuffle);
      expect(icon.icon?.fontFamily, 'MaterialIcons');
      expect(icon.icon?.fontPackage, isNull);
      expect(find.byIcon(CupertinoIcons.shuffle_medium), findsNothing);
    },
  );

  testWidgets(
    'aligns discovery toggle horizontally with reel action bar icons',
    (tester) async {
      await pumpFeed(tester);

      final discovery = tester.getRect(
        find.byKey(const Key('discovery_mode_toggle')),
      );
      // Compare circular hit targets (Containers), not glyph boxes — labels
      // can widen the action column without shifting the trailing circles.
      final speedCircle = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.speed),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(discovery.right, moreOrLessEquals(speedCircle.right, epsilon: 0.5));
      expect(discovery.center.dx, moreOrLessEquals(speedCircle.center.dx, epsilon: 0.5));
    },
  );

  testWidgets('enables discovery mode when top-right toggle is tapped',
      (tester) async {
    await pumpFeed(tester);
    expect(controller.discoveryMode, isFalse);

    await tester.tap(find.byKey(const Key('discovery_mode_toggle')));
    await settle(tester);

    expect(controller.discoveryMode, isTrue);
    expect(find.byIcon(Icons.shuffle_on), findsOneWidget);
    expect(controller.reels.first.id, 2);
  });
}
