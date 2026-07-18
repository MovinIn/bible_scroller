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
    iqBookId: '01',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test-device');

  int? lastBeforeId;
  int? lastCursor;
  ReelFeed forwardPage = const ReelFeed(items: [], nextCursor: null);
  ReelFeed backwardPage = const ReelFeed(items: [], nextCursor: null);

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    lastCursor = cursor;
    lastBeforeId = beforeId;
    if (beforeId != null) {
      return backwardPage;
    }
    if (cursor != null) {
      return forwardPage;
    }
    return ReelFeed(
      items: [
        _reel(id: 404, book: 'Exodus'),
        _reel(id: 405, book: 'Exodus', verse: 2),
        _reel(id: 405, book: 'Exodus', verse: 3),
      ],
      nextCursor: 405,
      prevCursor: 404,
    );
  }

  @override
  Future<List<String>> fetchBooks() async => const ['Genesis', 'Exodus'];

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    return const [
      BibleVersion(versionId: 'niv', name: 'New International Version'),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'autoplay_voice': false});
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_pagination_');
    final storage = StorageService();
    await storage.init(hivePath: tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('prepends earlier reels when prependPreviousPage is called', () async {
    final api = _FakeApi()
      ..backwardPage = ReelFeed(
        items: [_reel(id: 403, book: 'Genesis', chapter: 50, verse: 26)],
        nextCursor: 403,
        prevCursor: null,
      );
    final storage = StorageService();
    await storage.init(hivePath: tempDir.path);
    final controller = ReelsController(api: api, storage: storage);

    await controller.refreshFeed();
    expect(controller.reels.first.book, 'Exodus');
    expect(controller.canLoadPrevious, isTrue);

    final added = await controller.prependPreviousPage();

    expect(added, 1);
    expect(controller.reels.first.reference, 'Genesis 50:26');
    expect(controller.reels[1].book, 'Exodus');
    expect(api.lastBeforeId, 404);
  });

  test('appends next reels when ensureNextPageLoaded is called at end', () async {
    final api = _FakeApi()
      ..forwardPage = ReelFeed(
        items: [_reel(id: 406, book: 'Exodus', verse: 3)],
        nextCursor: null,
        prevCursor: null,
      );
    final storage = StorageService();
    await storage.init(hivePath: tempDir.path);
    final controller = ReelsController(api: api, storage: storage);

    await controller.refreshFeed();
    expect(controller.canLoadNext, isTrue);

    final loaded = await controller.ensureNextPageLoaded();

    expect(loaded, isTrue);
    expect(controller.reels.last.id, 406);
    expect(api.lastCursor, 405);
  });
}
