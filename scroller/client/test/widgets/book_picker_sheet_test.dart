import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/widgets/book_picker_sheet.dart';

void main() {
  testWidgets('shows books from list when sheet is opened', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationPickerSheet(
            books: const ['Genesis', 'John', 'Acts'],
            currentBook: 'John',
            currentChapter: 3,
            currentStartVerse: 16,
            loadChapters: (_) async => const [1, 2, 3],
            loadSections: (_, __) async => const [],
          ),
        ),
      ),
    );

    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('John'), findsOneWidget);
    expect(find.text('Acts'), findsOneWidget);
    expect(find.text('Choose book'), findsOneWidget);
  });

  testWidgets('shows checkmark on current book when sheet lists books', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationPickerSheet(
            books: const ['Genesis', 'John'],
            currentBook: 'John',
            currentChapter: 3,
            currentStartVerse: 16,
            loadChapters: (_) async => const [1],
            loadSections: (_, __) async => const [],
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

  testWidgets('shows chapter grid when book is tapped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationPickerSheet(
            books: const ['Genesis', 'John'],
            currentBook: 'John',
            currentChapter: 3,
            currentStartVerse: 16,
            loadChapters: (book) async {
              expect(book, 'John');
              return const [1, 2, 3];
            },
            loadSections: (_, __) async => const [],
          ),
        ),
      ),
    );

    await tester.tap(find.text('John'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('John'), findsWidgets);
  });

  testWidgets('shows section labels when chapter is tapped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationPickerSheet(
            books: const ['John'],
            currentBook: 'John',
            currentChapter: 3,
            currentStartVerse: 1,
            loadChapters: (_) async => const [3],
            loadSections: (book, chapter) async {
              expect(book, 'John');
              expect(chapter, 3);
              return const [
                VerseSection(
                  id: 10,
                  startVerse: 1,
                  endVerse: 4,
                  reference: 'John 3:1-4',
                ),
                VerseSection(
                  id: 11,
                  startVerse: 5,
                  endVerse: 8,
                  reference: 'John 3:5-8',
                ),
              ];
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('John'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(find.text('1–4'), findsOneWidget);
    expect(find.text('5–8'), findsOneWidget);
  });

  testWidgets('returns selected section reel id when section is tapped', (tester) async {
    LocationPickerResult? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showLocationPickerSheet(
                    context,
                    books: const ['John'],
                    currentBook: 'John',
                    currentChapter: 3,
                    currentStartVerse: 1,
                    loadChapters: (_) async => const [3],
                    loadSections: (_, __) async => const [
                      VerseSection(
                        id: 42,
                        startVerse: 1,
                        endVerse: 4,
                        reference: 'John 3:1-4',
                      ),
                    ],
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
    await tester.tap(find.text('John'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1–4'));
    await tester.pumpAndSettle();

    expect(selected?.reelId, 42);
  });

  testWidgets('returns to book list when back is pressed from chapters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationPickerSheet(
            books: const ['Genesis', 'John'],
            currentBook: 'John',
            currentChapter: 3,
            currentStartVerse: 16,
            loadChapters: (_) async => const [1, 2],
            loadSections: (_, __) async => const [],
          ),
        ),
      ),
    );

    await tester.tap(find.text('John'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('Choose book'), findsOneWidget);
  });
}
