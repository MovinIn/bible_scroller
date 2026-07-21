import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/screens/reels_feed_screen.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/utils/page_wheel_navigator.dart';
import 'package:bible_scroller/utils/voiceover_tap_action.dart';

class _FakeReelsController extends ReelsController {
  _FakeReelsController(this._fakeReels)
      : super(
          api: ApiClient(deviceId: 'test-device'),
          storage: StorageService(),
        ) {
    loading = false;
  }

  final List<Reel> _fakeReels;
  final List<int> visibleIndexes = [];
  int toggleCalls = 0;

  @override
  List<Reel> get reels => List.unmodifiable(_fakeReels);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onReelVisible(int index) async {
    visibleIndexes.add(index);
  }

  @override
  VoiceoverTapAction peekVoiceoverTapAction(Reel reel) => VoiceoverTapAction.pause;

  @override
  Future<VoiceoverTapAction> toggleVoiceoverPlayback(Reel reel) async {
    toggleCalls += 1;
    return VoiceoverTapAction.pause;
  }
}

Reel _reel(int id, String reference) {
  return Reel(
    id: id,
    reference: reference,
    book: 'John',
    chapter: 3,
    startVerse: id,
    endVerse: id,
    slug: 'John_3_$id-$id',
    imageUrl: 'https://example.com/$id.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

Widget _harness(ReelsController controller) {
  return ChangeNotifierProvider<ReelsController>.value(
    value: controller,
    child: MaterialApp(
      home: ReelsFeedScreen(
        wheelNavigator: PageWheelNavigator(cooldown: Duration.zero),
      ),
    ),
  );
}

void main() {
  final reels = [_reel(1, 'John 3:1'), _reel(2, 'John 3:2'), _reel(3, 'John 3:3')];

  testWidgets('advances to next reel when one wheel notch scrolls down', (tester) async {
    final controller = _FakeReelsController(reels);
    await tester.pumpWidget(_harness(controller));
    await tester.pump();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(PageView)));
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, 120)),
    );
    await tester.pumpAndSettle();

    expect(controller.visibleIndexes, contains(1));
    expect(find.text('John 3:2'), findsOneWidget);
  });

  testWidgets('returns to previous reel when one wheel notch scrolls up', (tester) async {
    final controller = _FakeReelsController(reels);
    await tester.pumpWidget(_harness(controller));
    await tester.pump();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(PageView)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pumpAndSettle();

    expect(find.text('John 3:1'), findsOneWidget);
  });

  testWidgets('advances to next reel when body is swiped up', (tester) async {
    final controller = _FakeReelsController(reels);
    await tester.pumpWidget(_harness(controller));
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    expect(controller.visibleIndexes, contains(1));
    expect(find.text('John 3:2'), findsOneWidget);
  });

  testWidgets('toggles voiceover when reel body is tapped', (tester) async {
    final controller = _FakeReelsController(reels);
    await tester.pumpWidget(_harness(controller));
    await tester.pump();

    await tester.tapAt(const Offset(120, 300));
    await tester.pumpAndSettle();

    expect(controller.toggleCalls, 1);
  });
}
