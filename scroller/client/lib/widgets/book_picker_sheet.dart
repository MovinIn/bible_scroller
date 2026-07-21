import 'package:flutter/material.dart';

import '../models/models.dart';

class LocationPickerResult {
  const LocationPickerResult({required this.reelId});

  final int reelId;
}

Future<LocationPickerResult?> showLocationPickerSheet(
  BuildContext context, {
  required List<String> books,
  required String currentBook,
  required int currentChapter,
  required int currentStartVerse,
  required Future<List<int>> Function(String book) loadChapters,
  required Future<List<VerseSection>> Function(String book, int chapter)
      loadSections,
}) {
  return showModalBottomSheet<LocationPickerResult>(
    context: context,
    backgroundColor: const Color(0xFF121212),
    isScrollControlled: true,
    builder: (context) => LocationPickerSheet(
      books: books,
      currentBook: currentBook,
      currentChapter: currentChapter,
      currentStartVerse: currentStartVerse,
      loadChapters: loadChapters,
      loadSections: loadSections,
    ),
  );
}

enum _PickerStep { books, chapters, sections }

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({
    super.key,
    required this.books,
    required this.currentBook,
    required this.currentChapter,
    required this.currentStartVerse,
    required this.loadChapters,
    required this.loadSections,
  });

  final List<String> books;
  final String currentBook;
  final int currentChapter;
  final int currentStartVerse;
  final Future<List<int>> Function(String book) loadChapters;
  final Future<List<VerseSection>> Function(String book, int chapter)
      loadSections;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  _PickerStep _step = _PickerStep.books;
  String? _selectedBook;
  int? _selectedChapter;
  List<int> _chapters = const [];
  List<VerseSection> _sections = const [];
  bool _loading = false;

  Future<void> _openChapters(String book) async {
    setState(() {
      _loading = true;
      _selectedBook = book;
      _step = _PickerStep.chapters;
      _chapters = const [];
    });
    try {
      final chapters = await widget.loadChapters(book);
      if (!mounted) {
        return;
      }
      setState(() {
        _chapters = chapters;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _chapters = const [];
        _loading = false;
      });
    }
  }

  Future<void> _openSections(int chapter) async {
    final book = _selectedBook;
    if (book == null) {
      return;
    }
    setState(() {
      _loading = true;
      _selectedChapter = chapter;
      _step = _PickerStep.sections;
      _sections = const [];
    });
    try {
      final sections = await widget.loadSections(book, chapter);
      if (!mounted) {
        return;
      }
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sections = const [];
        _loading = false;
      });
    }
  }

  void _goBack() {
    setState(() {
      if (_step == _PickerStep.sections) {
        _step = _PickerStep.chapters;
        _selectedChapter = null;
        _sections = const [];
      } else if (_step == _PickerStep.chapters) {
        _step = _PickerStep.books;
        _selectedBook = null;
        _chapters = const [];
      }
    });
  }

  String get _title {
    switch (_step) {
      case _PickerStep.books:
        return 'Choose book';
      case _PickerStep.chapters:
        return _selectedBook ?? 'Choose chapter';
      case _PickerStep.sections:
        final book = _selectedBook ?? '';
        final chapter = _selectedChapter;
        return chapter == null ? book : '$book $chapter';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBack = _step != _PickerStep.books;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            ListTile(
              leading: showBack
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _goBack,
                    )
                  : null,
              title: Text(_title),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_step) {
      case _PickerStep.books:
        return ListView(
          children: [
            ...widget.books.map(
              (book) => ListTile(
                title: Text(book),
                trailing: widget.currentBook == book
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => _openChapters(book),
              ),
            ),
          ],
        );
      case _PickerStep.chapters:
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _chapters.length,
          itemBuilder: (context, index) {
            final chapter = _chapters[index];
            final isCurrent = _selectedBook == widget.currentBook &&
                chapter == widget.currentChapter;
            return _GridCell(
              label: '$chapter',
              selected: isCurrent,
              onTap: () => _openSections(chapter),
            );
          },
        );
      case _PickerStep.sections:
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
          ),
          itemCount: _sections.length,
          itemBuilder: (context, index) {
            final section = _sections[index];
            final isCurrent = section.startVerse == widget.currentStartVerse &&
                _selectedBook == widget.currentBook &&
                _selectedChapter == widget.currentChapter;
            return _GridCell(
              label: section.label,
              selected: isCurrent,
              onTap: () => Navigator.pop(
                context,
                LocationPickerResult(reelId: section.id),
              ),
            );
          },
        );
    }
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white24 : Colors.white10,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
