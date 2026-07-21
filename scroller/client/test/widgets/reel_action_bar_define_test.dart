import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/widgets/reel_action_bar.dart';

void main() {
  const reel = Reel(
    id: 1,
    reference: 'John 3:16',
    book: 'John',
    chapter: 3,
    startVerse: 16,
    endVerse: 16,
    slug: 'John_3_16-16',
    imageUrl: 'https://example.com/image.png',
    iqBookId: '43',
    likeCount: 12,
    commentCount: 4,
    likedByMe: true,
  );

  testWidgets('shows define icon below translation icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'esv',
            isMuted: false,
            defineModeEnabled: false,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: _noop,
            onVoiceTap: _noop,
          ),
        ),
      ),
    );

    final translate = tester.getCenter(find.byIcon(Icons.translate));
    final define = tester.getCenter(find.byIcon(Icons.menu_book_outlined));
    expect(define.dy, greaterThan(translate.dy));
    expect(find.text('Define'), findsOneWidget);
  });

  testWidgets('highlights define icon when define mode is enabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'esv',
            isMuted: false,
            defineModeEnabled: true,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: _noop,
            onVoiceTap: _noop,
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.menu_book));
    expect(icon.color, Colors.amberAccent);
    expect(find.text('BSB'), findsOneWidget);
  });

  testWidgets('calls onDefineTap when define button is tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'esv',
            isMuted: false,
            defineModeEnabled: false,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: () => tapped = true,
            onVoiceTap: _noop,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pump();
    expect(tapped, isTrue);
  });
}

void _noop() {}
