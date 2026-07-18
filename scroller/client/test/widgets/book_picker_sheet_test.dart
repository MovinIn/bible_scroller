import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/widgets/book_picker_sheet.dart';

void main() {
  testWidgets('shows books from list when sheet is opened', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookPickerSheet(
            books: const ['Genesis', 'John', 'Acts'],
            currentBook: 'John',
          ),
        ),
      ),
    );

    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('John'), findsOneWidget);
    expect(find.text('Acts'), findsOneWidget);
  });

  testWidgets('returns selected book when list item is tapped', (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showBookPickerSheet(
                    context,
                    books: const ['Genesis', 'John', 'Acts'],
                    currentBook: 'John',
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acts'));
    await tester.pumpAndSettle();

    expect(selected, 'Acts');
  });

  testWidgets('shows checkmark on current book when sheet lists books', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookPickerSheet(
            books: const ['Genesis', 'John'],
            currentBook: 'John',
          ),
        ),
      ),
    );

    final johnTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'John'),
    );
    expect(johnTile.trailing, isA<Icon>());
    expect((johnTile.trailing! as Icon).icon, Icons.check);

    final genesisTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Genesis'),
    );
    expect(genesisTile.trailing, isNull);
  });
}
