import 'package:flutter/cupertino.dart';
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

  testWidgets(
    'uses Material Icons.speed with MaterialIcons font for speed action',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReelActionBar(
              reel: reel,
              translationVersion: 'esv',
              isMuted: false,
              defineModeEnabled: false,
              playbackSpeed: 1.0,
              onLike: _noop,
              onCommentsTap: _noop,
              onTranslationTap: _noop,
              onDefineTap: _noop,
              onVoiceTap: _noop,
              onSpeedTap: _noop,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.speed));
      expect(icon.icon, Icons.speed);
      expect(icon.icon?.fontFamily, 'MaterialIcons');
      expect(icon.icon?.fontPackage, isNull);
      expect(find.byIcon(CupertinoIcons.speedometer), findsNothing);
    },
  );

  testWidgets('shows speed icon below voice icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'esv',
            isMuted: false,
            defineModeEnabled: false,
            playbackSpeed: 1.0,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: _noop,
            onVoiceTap: _noop,
            onSpeedTap: _noop,
          ),
        ),
      ),
    );

    final voice = tester.getCenter(find.byIcon(Icons.volume_up_outlined));
    final speed = tester.getCenter(find.byIcon(Icons.speed));
    expect(speed.dy, greaterThan(voice.dy));
  });

  testWidgets('shows current playback speed as label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'esv',
            isMuted: false,
            defineModeEnabled: false,
            playbackSpeed: 1.5,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: _noop,
            onVoiceTap: _noop,
            onSpeedTap: _noop,
          ),
        ),
      ),
    );

    expect(find.text('1.5x'), findsOneWidget);
  });

  testWidgets('calls onSpeedTap when speed button is tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelActionBar(
            reel: reel,
            translationVersion: 'esv',
            isMuted: false,
            defineModeEnabled: false,
            playbackSpeed: 1.0,
            onLike: _noop,
            onCommentsTap: _noop,
            onTranslationTap: _noop,
            onDefineTap: _noop,
            onVoiceTap: _noop,
            onSpeedTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.speed));
    await tester.pump();
    expect(tapped, isTrue);
  });
}

void _noop() {}
