import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

Reel _reel({required int id, required String book, int verse = 1}) {
  return Reel(
    id: id,
    reference: '$book 1:$verse',
    book: book,
    chapter: 1,
    startVerse: verse,
    endVerse: verse,
    slug: '${book}_1_$verse-$verse',
    imageUrl: 'https://example.com/$id.png',
    iqBookId: '01',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test-device');

  int sequentialFetchCount = 0;
  int discoveryFetchCount = 0;
  List<int>? lastExcludeIds;
  ReelFeed sequentialFeed = ReelFeed(
    items: [_reel(id: 1, book: 'Genesis')],
    nextCursor: null,
    prevCursor: null,
  );
  ReelFeed discoveryFeed = ReelFeed(
    items: [_reel(id: 10, book: 'John', verse: 16)],
    nextCursor: null,
    prevCursor: null,
  );
  ReelFeed discoveryMoreFeed = ReelFeed(
    items: [_reel(id: 20, book: 'Psalms', verse: 1)],
    nextCursor: null,
    prevCursor: null,
  );

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    sequentialFetchCount += 1;
    return sequentialFeed;
  }

  @override
  Future<ReelFeed> fetchDiscoveryReels({
    int limit = 10,
    List<int> excludeIds = const [],
  }) async {
    discoveryFetchCount += 1;
    lastExcludeIds = List<int>.from(excludeIds);
    if (excludeIds.isNotEmpty) {
      return discoveryMoreFeed;
    }
    return discoveryFeed;
  }

  @override
  Future<List<String>> fetchBooks() async => const ['Genesis', 'John'];

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    return const [
      BibleVersion(versionId: 'esv', name: 'English Standard Version'),
    ];
  }

  @override
  Future<BibleVerse> fetchVerse({
    required Reel reel,
    required String versionId,
    int? startVerse,
    int? endVerse,
  }) async {
    return BibleVerse(
      reference: reel.reference,
      versionId: versionId,
      text: 'text',
    );
  }

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    return BibleAudio(
      reference: reel.reference,
      versionId: versionId,
      audioUrl: '',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'autoplay_voice': false});
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_discovery_');
    Hive.init(tempDir.path);
    storage = StorageService();
    await storage.init(hivePath: tempDir.path);
    await storage.cacheVerseText(reelId: 0, versionId: 'warm', text: 'warm');
  });

  tearDown(() async {
    await pumpEventQueue();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('loads discoveryMode true when preference was previously stored', () async {
    await storage.saveDiscoveryMode(true);
    final api = _FakeApi();
    final controller = ReelsController(api: api, storage: storage);

    await controller.initialize();

    expect(controller.discoveryMode, isTrue);
    expect(api.discoveryFetchCount, 1);
    expect(controller.reels.single.id, 10);
  });

  test('loads sequential feed when discovery mode preference is false', () async {
    final api = _FakeApi();
    final controller = ReelsController(api: api, storage: storage);

    await controller.initialize();

    expect(controller.discoveryMode, isFalse);
    expect(api.sequentialFetchCount, 1);
    expect(api.discoveryFetchCount, 0);
    expect(controller.reels.single.id, 1);
  });

  test('replaces feed with discovery batch when discovery mode is enabled', () async {
    final api = _FakeApi();
    final controller = ReelsController(api: api, storage: storage);
    await controller.initialize();
    expect(controller.reels.single.id, 1);

    await controller.setDiscoveryMode(true);

    expect(controller.discoveryMode, isTrue);
    expect(await storage.readDiscoveryMode(), isTrue);
    expect(controller.reels.single.id, 10);
    expect(controller.canLoadPrevious, isFalse);
  });

  test('restores sequential feed when discovery mode is disabled', () async {
    await storage.saveDiscoveryMode(true);
    final api = _FakeApi();
    final controller = ReelsController(api: api, storage: storage);
    await controller.initialize();
    expect(controller.reels.single.id, 10);
    final discoveryCallsBeforeDisable = api.discoveryFetchCount;
    final sequentialBeforeDisable = api.sequentialFetchCount;

    await controller.setDiscoveryMode(false);

    expect(controller.discoveryMode, isFalse);
    expect(await storage.readDiscoveryMode(), isFalse);
    expect(api.sequentialFetchCount, sequentialBeforeDisable + 1);
    expect(api.discoveryFetchCount, discoveryCallsBeforeDisable);
    expect(controller.reels.single.id, 1);
  });

  test('passes session reel ids as exclude when loading more in discovery mode', () async {
    final api = _FakeApi()
      ..discoveryFeed = ReelFeed(
        items: [
          _reel(id: 10, book: 'John', verse: 16),
          _reel(id: 11, book: 'John', verse: 17),
          _reel(id: 12, book: 'John', verse: 18),
        ],
        nextCursor: 12,
        prevCursor: null,
      );
    final controller = ReelsController(api: api, storage: storage);
    await controller.initialize();
    await controller.setDiscoveryMode(true);
    await pumpEventQueue();
    expect(controller.reels.map((r) => r.id), [10, 11, 12]);
    expect(controller.canLoadNext, isTrue);

    await controller.ensureNextPageLoaded();

    expect(api.lastExcludeIds, [10, 11, 12]);
    expect(controller.reels.map((r) => r.id), [10, 11, 12, 20]);
  });

  test('disables discovery mode when jumping to a section', () async {
    final api = _FakeApi()
      ..sequentialFeed = ReelFeed(
        items: [_reel(id: 50, book: 'Romans')],
        nextCursor: null,
        prevCursor: null,
      );
    final controller = ReelsController(api: api, storage: storage);
    await controller.initialize();
    await controller.setDiscoveryMode(true);
    expect(controller.discoveryMode, isTrue);

    final index = await controller.jumpToSection(50);

    expect(index, 0);
    expect(controller.discoveryMode, isFalse);
    expect(await storage.readDiscoveryMode(), isFalse);
    expect(controller.reels.single.id, 50);
  });
}
