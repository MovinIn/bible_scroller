import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

Reel _reel({
  required int id,
  required String book,
  int chapter = 1,
  int verse = 1,
}) {
  return Reel(
    id: id,
    reference: '$book $chapter:$verse',
    book: book,
    chapter: chapter,
    startVerse: verse,
    endVerse: verse,
    slug: '${book}_${chapter}_$verse-$verse',
    imageUrl: 'https://example.com/$id.png',
    iqBookId: '00',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test-device');

  String? lastBookQuery;
  List<Reel> bookJumpItems = const [];
  List<String> books = const ['Genesis', 'John', 'Acts'];

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    lastBookQuery = book;
    if (book != null) {
      return ReelFeed(items: bookJumpItems, nextCursor: null);
    }
    return const ReelFeed(items: [], nextCursor: null);
  }

  @override
  Future<List<String>> fetchBooks() async => books;

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    return const [
      BibleVersion(versionId: 'niv', name: 'New International Version'),
    ];
  }

  @override
  Future<BibleVerse> fetchVerse({required Reel reel, required String versionId}) async {
    return BibleVerse(
      reference: reel.reference,
      versionId: versionId,
      text: 'Verse text',
    );
  }

  @override
  Future<BibleAudio> fetchAudio({required Reel reel, required String versionId}) async {
    return BibleAudio(
      reference: reel.reference,
      versionId: versionId,
      audioUrl: '',
    );
  }
}

Future<void> _waitForVerseText(ReelsController controller, Reel reel) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await pumpEventQueue();
    if (controller.verseTextFor(reel) != 'Loading verse…') {
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_jump_');
    storage = StorageService();
    await storage.init(hivePath: tempDir.path);
    await storage.cacheVerseText(reelId: 0, versionId: 'warm', text: 'warm');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('replaces feed with first page of book when jumpToBook succeeds', () async {
    final api = _FakeApi()
      ..bookJumpItems = [
        _reel(id: 10, book: 'John', chapter: 1),
        _reel(id: 11, book: 'John', chapter: 3, verse: 16),
        _reel(id: 12, book: 'Acts'),
      ];
    final controller = ReelsController(api: api, storage: storage)
      ..autoplayVoice = false;

    final index = await controller.jumpToBook('John');
    await _waitForVerseText(controller, controller.reels.first);

    expect(api.lastBookQuery, 'John');
    expect(index, 0);
    expect(controller.reels.map((r) => r.id).toList(), [10, 11, 12]);
    expect(controller.currentReel?.book, 'John');
  });

  test('returns null and leaves feed unchanged when book has no reels', () async {
    final api = _FakeApi()..bookJumpItems = const [];
    final controller = ReelsController(api: api, storage: storage)
      ..autoplayVoice = false;
    api.bookJumpItems = [_reel(id: 1, book: 'Genesis')];
    await controller.jumpToBook('Genesis');
    await _waitForVerseText(controller, controller.reels.first);
    api.bookJumpItems = const [];

    final index = await controller.jumpToBook('Romans');

    expect(index, isNull);
    expect(controller.reels.map((r) => r.id).toList(), [1]);
    expect(controller.currentReel?.book, 'Genesis');
  });

  test('loads available books when ensureBooksLoaded is called', () async {
    final api = _FakeApi()..books = const ['Genesis', 'John'];
    final controller = ReelsController(api: api, storage: storage)
      ..autoplayVoice = false;

    await controller.ensureBooksLoaded();
    controller.dispose();

    expect(controller.books, ['Genesis', 'John']);
  });
}
