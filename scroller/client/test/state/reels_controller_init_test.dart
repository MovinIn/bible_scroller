import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

Reel _reel({required int id, required String book}) {
  return Reel(
    id: id,
    reference: '$book 1:1',
    book: book,
    chapter: 1,
    startVerse: 1,
    endVerse: 1,
    slug: '${book}_1_1-1',
    imageUrl: 'https://example.com/$id.png',
    iqBookId: '01',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _TrackingApi extends ApiClient {
  _TrackingApi() : super(deviceId: 'test-device');

  bool fetchBooksCalled = false;
  bool fetchVersionsCalled = false;
  int fetchBooksCallCount = 0;
  final feedReady = Completer<void>();
  final verseReady = Completer<void>();
  Completer<void>? booksReady;
  Completer<void>? versionsReady;

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    if (cursor == null && beforeId == null && book == null) {
      await feedReady.future;
    }
    return ReelFeed(items: [_reel(id: 1, book: 'Genesis')], nextCursor: null);
  }

  @override
  Future<List<String>> fetchBooks() async {
    fetchBooksCalled = true;
    fetchBooksCallCount += 1;
    final gate = booksReady;
    if (gate != null) {
      await gate.future;
    }
    return const ['Genesis', 'John'];
  }

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    fetchVersionsCalled = true;
    final gate = versionsReady;
    if (gate != null) {
      await gate.future;
    }
    return const [
      BibleVersion(versionId: 'niv', name: 'New International Version'),
    ];
  }

  @override
  Future<BibleVerse> fetchVerse({required Reel reel, required String versionId}) async {
    await verseReady.future;
    return BibleVerse(
      reference: reel.reference,
      versionId: versionId,
      text: 'In the beginning',
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
    SharedPreferences.setMockInitialValues({'autoplay_voice': false});
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_init_');
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

  test('shows feed before books catalog loads when initialize runs', () async {
    final api = _TrackingApi();
    final controller = ReelsController(api: api, storage: storage);

    final initFuture = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.loading, isTrue);
    expect(api.fetchBooksCalled, isFalse);
    expect(api.fetchVersionsCalled, isFalse);

    api.feedReady.complete();
    await initFuture;
    api.verseReady.complete();
    await _waitForVerseText(controller, controller.reels.first);

    expect(controller.loading, isFalse);
    expect(controller.reels, hasLength(1));
    expect(api.fetchBooksCalled, isFalse);
    expect(api.fetchVersionsCalled, isFalse);
  });

  test('clears loading before onReelVisible verse fetch completes when refreshFeed runs', () async {
    final api = _TrackingApi()..feedReady.complete();
    final controller = ReelsController(api: api, storage: storage);

    final refreshFuture = controller.refreshFeed();
    await Future<void>.delayed(Duration.zero);

    expect(controller.loading, isFalse);
    expect(controller.reels, hasLength(1));
    expect(controller.verseTextFor(controller.reels.first), 'Loading verse…');

    api.verseReady.complete();
    await refreshFuture;
    await _waitForVerseText(controller, controller.reels.first);

    expect(controller.verseTextFor(controller.reels.first), 'In the beginning');
  });

  test('loads books when ensureBooksLoaded is called', () async {
    final api = _TrackingApi()..feedReady.complete();
    final controller = ReelsController(api: api, storage: storage);

    await controller.ensureBooksLoaded();

    expect(controller.books, ['Genesis', 'John']);
    expect(api.fetchBooksCalled, isTrue);
  });

  test('loads versions when ensureVersionsLoaded is called', () async {
    final api = _TrackingApi()..feedReady.complete();
    final controller = ReelsController(api: api, storage: storage);

    await controller.ensureVersionsLoaded();

    expect(controller.versions, hasLength(1));
    expect(controller.versions.first.versionId, 'niv');
    expect(api.fetchVersionsCalled, isTrue);
  });

  test('awaits in-flight books catalog when ensureBooksLoaded is called concurrently', () async {
    final api = _TrackingApi()
      ..feedReady.complete()
      ..booksReady = Completer<void>();
    final controller = ReelsController(api: api, storage: storage);

    final first = controller.ensureBooksLoaded();
    await Future<void>.delayed(Duration.zero);
    expect(api.fetchBooksCallCount, 1);
    expect(controller.books, isEmpty);

    final second = controller.ensureBooksLoaded();
    api.booksReady!.complete();
    await Future.wait([first, second]);

    expect(api.fetchBooksCallCount, 1);
    expect(controller.books, ['Genesis', 'John']);
  });

  test('fetches verse once when refreshFeed is called while prior visibility work is in flight', () async {
    final api = _TrackingApi()..feedReady.complete();
    var fetchVerseCount = 0;
    final countingApi = _CountingVerseApi(api, onFetch: () => fetchVerseCount += 1);
    final controller = ReelsController(api: countingApi, storage: storage)
      ..autoplayVoice = false;

    unawaited(controller.refreshFeed());
    await Future<void>.delayed(Duration.zero);
    unawaited(controller.refreshFeed());
    await Future<void>.delayed(Duration.zero);

    api.verseReady.complete();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();

    expect(fetchVerseCount, 1);
  });
}

class _CountingVerseApi extends ApiClient {
  _CountingVerseApi(this._inner, {required this.onFetch})
      : super(deviceId: 'test-device');

  final _TrackingApi _inner;
  final void Function() onFetch;

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) =>
      _inner.fetchReels(
        cursor: cursor,
        beforeId: beforeId,
        fromId: fromId,
        book: book,
        limit: limit,
      );

  @override
  Future<List<String>> fetchBooks() => _inner.fetchBooks();

  @override
  Future<List<BibleVersion>> fetchVersions() => _inner.fetchVersions();

  @override
  Future<BibleVerse> fetchVerse({required Reel reel, required String versionId}) async {
    onFetch();
    return _inner.fetchVerse(reel: reel, versionId: versionId);
  }

  @override
  Future<BibleAudio> fetchAudio({required Reel reel, required String versionId}) =>
      _inner.fetchAudio(reel: reel, versionId: versionId);
}
