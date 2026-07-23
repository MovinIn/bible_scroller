import 'package:bible_scroller/utils/app_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses 1500ms duration when building a snack bar', () {
    final snackBar = AppSnackBar.build(message: 'Saved');

    expect(snackBar.duration, const Duration(milliseconds: 1500));
  });

  testWidgets('shows snack bar with 1500ms duration when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => AppSnackBar.show(context, 'Hello'),
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(milliseconds: 1500));
    expect(find.text('Hello'), findsOneWidget);
  });
}
