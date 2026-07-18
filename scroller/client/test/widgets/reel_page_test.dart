import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/widgets/reel_page.dart';

class _FakeReelsController extends ReelsController {
  _FakeReelsController()
      : super(
          api: ApiClient(deviceId: 'test-device'),
          storage: StorageService(),
        );
}

const _reel = Reel(
  id: 1,
  reference: 'John 3:16',
  book: 'John',
  chapter: 3,
  startVerse: 16,
  endVerse: 16,
  slug: 'John_3_16-16',
  imageUrl: 'https://example.com/image.png',
  iqBookId: '43',
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
);

const _reelTwo = Reel(
  id: 2,
  reference: 'John 1:1',
  book: 'John',
  chapter: 1,
  startVerse: 1,
  endVerse: 1,
  slug: 'John_1_1-1',
  imageUrl: 'https://example.com/image2.png',
  iqBookId: '43',
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
);

void main() {
  testWidgets('invokes onBodyTap when reel body is tapped', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelPage(
            reel: _reel,
            controller: _FakeReelsController(),
            onCommentsTap: () {},
            onTranslationTap: () {},
            onVoiceTap: () {},
            onBodyTap: () => taps += 1,
          ),
        ),
      ),
    );

    // Tap the body away from the right-side action bar.
    await tester.tapAt(const Offset(120, 300));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('shows current reel book in top-left picker when reel is displayed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelPage(
            reel: _reel,
            controller: _FakeReelsController(),
            onCommentsTap: () {},
            onTranslationTap: () {},
            onVoiceTap: () {},
            onBookTap: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('book_picker_button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('book_picker_button')),
        matching: find.text('John'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('invokes onBookTap when book picker is tapped', (tester) async {
    var bookTaps = 0;
    var bodyTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelPage(
            reel: _reel,
            controller: _FakeReelsController(),
            onCommentsTap: () {},
            onTranslationTap: () {},
            onVoiceTap: () {},
            onBodyTap: () => bodyTaps += 1,
            onBookTap: () => bookTaps += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('book_picker_button')));
    await tester.pump();

    expect(bookTaps, 1);
    expect(bodyTaps, 0);
  });

  testWidgets(
    'advances PageView page when vertical drag starts over body tap target',
    (tester) async {
      final pageController = PageController();
      addTearDown(pageController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pageController,
              scrollDirection: Axis.vertical,
              children: [
                ReelPage(
                  reel: _reel,
                  controller: _FakeReelsController(),
                  onCommentsTap: () {},
                  onTranslationTap: () {},
                  onVoiceTap: () {},
                  onBodyTap: () {},
                ),
                ReelPage(
                  reel: _reelTwo,
                  controller: _FakeReelsController(),
                  onCommentsTap: () {},
                  onTranslationTap: () {},
                  onVoiceTap: () {},
                  onBodyTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pageController.page, 0);

      await tester.drag(
        find.byKey(const Key('reel_body_tap_target')).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(pageController.page, 1);
    },
  );

  testWidgets(
    'does not invoke onBodyTap when pointer moves beyond tap slop',
    (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReelPage(
              reel: _reel,
              controller: _FakeReelsController(),
              onCommentsTap: () {},
              onTranslationTap: () {},
              onVoiceTap: () {},
              onBodyTap: () => taps += 1,
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(120, 300));
      await gesture.moveBy(const Offset(0, -40));
      await gesture.up();
      await tester.pump();

      expect(taps, 0);
    },
  );

  testWidgets(
    'body tap target is not an opaque GestureDetector',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReelPage(
              reel: _reel,
              controller: _FakeReelsController(),
              onCommentsTap: () {},
              onTranslationTap: () {},
              onVoiceTap: () {},
              onBodyTap: () {},
            ),
          ),
        ),
      );

      final bodyTarget = tester.widget(find.byKey(const Key('reel_body_tap_target')));
      expect(bodyTarget, isA<Listener>());
      final listener = bodyTarget as Listener;
      expect(listener.behavior, HitTestBehavior.translucent);
    },
  );
}
