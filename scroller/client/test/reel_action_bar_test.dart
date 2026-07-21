import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/widgets/reel_action_bar.dart';

void main() {
  testWidgets('shows like count when reel action bar is rendered', (tester) async {
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

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'kjv',
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

    expect(find.text('12'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('KJV'), findsOneWidget);
  });

  testWidgets('shows volume up icon when voice is unmuted', (tester) async {
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
      likeCount: 0,
      commentCount: 0,
      likedByMe: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'niv',
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

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_outlined), findsNothing);
  });

  testWidgets('shows volume off icon when voice is muted', (tester) async {
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
      likeCount: 0,
      commentCount: 0,
      likedByMe: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'niv',
            isMuted: true,
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

    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('calls onVoiceTap when mute button is tapped', (tester) async {
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
      likeCount: 0,
      commentCount: 0,
      likedByMe: false,
    );

    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'niv',
            isMuted: false,
            defineModeEnabled: false,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: _noop,
            onVoiceTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();

    expect(tapped, isTrue);
  });
}

void _noop() {}
