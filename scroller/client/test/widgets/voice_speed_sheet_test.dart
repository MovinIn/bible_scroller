import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/widgets/voice_speed_sheet.dart';

void main() {
  testWidgets('shows speed slider with minimum 0.5 and maximum 2.0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceSpeedSheet(
            speed: 1.0,
            onSpeedChanged: (_) {},
            onSpeedChangeEnd: (_) {},
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0.5);
    expect(slider.max, 2.0);
    expect(slider.value, 1.0);
  });

  testWidgets('shows current speed label when sheet is rendered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceSpeedSheet(
            speed: 1.5,
            onSpeedChanged: (_) {},
            onSpeedChangeEnd: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('1.5x'), findsOneWidget);
  });

  testWidgets('calls onSpeedChanged with 1.5 when dragged to mid-high range',
      (tester) async {
    double? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VoiceSpeedSheet(
              speed: 1.0,
              onSpeedChanged: (value) => reported = value,
              onSpeedChangeEnd: (_) {},
            ),
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    final box = tester.getRect(slider);
    // Slider range 0.5–2.0 with 6 divisions; tap near 1.5 (2/3 along track).
    await tester.tapAt(Offset(box.left + box.width * (2 / 3), box.center.dy));
    await tester.pumpAndSettle();

    expect(reported, 1.5);
  });

  testWidgets('calls onSpeedChangeEnd with final value when drag ends',
      (tester) async {
    double? ended;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VoiceSpeedSheet(
              speed: 1.0,
              onSpeedChanged: (_) {},
              onSpeedChangeEnd: (value) => ended = value,
            ),
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    final box = tester.getRect(slider);
    final start = Offset(box.left + box.width * 0.5, box.center.dy);
    final end = Offset(box.left + box.width * (2 / 3), box.center.dy);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    expect(ended, isNull);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(ended, 1.5);
  });
}
