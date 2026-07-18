import 'package:flutter/material.dart';

Future<String?> showBookPickerSheet(
  BuildContext context, {
  required List<String> books,
  required String currentBook,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF121212),
    builder: (context) => BookPickerSheet(
      books: books,
      currentBook: currentBook,
    ),
  );
}

class BookPickerSheet extends StatelessWidget {
  const BookPickerSheet({
    super.key,
    required this.books,
    required this.currentBook,
  });

  final List<String> books;
  final String currentBook;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        children: [
          const ListTile(title: Text('Choose book')),
          ...books.map(
            (book) => ListTile(
              title: Text(book),
              trailing: currentBook == book ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, book),
            ),
          ),
        ],
      ),
    );
  }
}
