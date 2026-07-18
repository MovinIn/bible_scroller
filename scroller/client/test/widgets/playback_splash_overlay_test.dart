import 'package:bible_scroller/utils/playback_splash_icon.dart';
import 'package:bible_scroller/widgets/playback_splash_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows pause icon in center when pause flash is triggered', (tester) async {
    final controller = PlaybackSplashController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.blue),
              PlaybackSplashOverlay(controller: controller),
            ],
          ),
        ),
      ),
    );

    controller.flash(PlaybackSplashIcon.pause);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('playback_splash_overlay')), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('shows play icon in center when play flash is triggered', (tester) async {
    final controller = PlaybackSplashController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.blue),
              PlaybackSplashOverlay(controller: controller),
            ],
          ),
        ),
      ),
    );

    controller.flash(PlaybackSplashIcon.play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('hides splash after flash animation completes', (tester) async {
    final controller = PlaybackSplashController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSplashOverlay(controller: controller),
        ),
      ),
    );

    controller.flash(PlaybackSplashIcon.play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('playback_splash_overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playback_splash_overlay')), findsNothing);
  });
}
