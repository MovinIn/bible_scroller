import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:bible_scroller/audio/voice_audio_player.dart';
import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

Reel _reel(int id) {
  return Reel(
    id: id,
    reference: 'John 3:$id',
    book: 'John',
    chapter: 3,
    startVerse: id,
    endVerse: id,
    slug: 'John_3_$id-$id',
    imageUrl: 'https://example.com/$id.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _FakeStorage extends StorageService {
  @override
  Future<String> readTranslationVersion({String fallback = 'esv'}) async => 'esv';

  @override
  Future<void> saveTranslationVersion(String versionId) async {}

  @override
  Future<bool> readAutoplayVoice({bool fallback = true}) async => false;

  @override
  Future<void> saveAutoplayVoice(bool enabled) async {}

  @override
  Future<bool> readVoiceMuted({bool fallback = false}) async => false;

  @override
  Future<void> saveVoiceMuted(bool muted) async {}

  @override
  Future<double> readVoicePlaybackSpeed({
    double fallback = StorageService.defaultVoicePlaybackSpeed,
  }) async =>
      fallback;

  @override
  Future<void> saveVoicePlaybackSpeed(double speed) async {}

  @override
  Future<bool> readDiscoveryMode({bool fallback = false}) async => false;

  @override
  Future<void> saveDiscoveryMode(bool enabled) async {}

  @override
  Future<String?> readDeviceId() async => 'test';

  @override
  Future<void> saveDeviceId(String deviceId) async {}

  @override
  Future<void> cacheVerseText({
    required int reelId,
    required String versionId,
    required String text,
  }) async {}

  @override
  Future<String?> readCachedVerseText({
    required int reelId,
    required String versionId,
  }) async =>
      null;
}

class _FakePlayer implements VoiceAudioPlayer {
  final _positions = StreamController<Duration>.broadcast();
  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  String? url;
  int setUrlCallCount = 0;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _state;

  @override
  Future<Duration?> setUrl(String url) async {
    setUrlCallCount += 1;
    this.url = url;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> play() async {
    _playing = true;
    _state = ProcessingState.ready;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _state = ProcessingState.idle;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {
    await _positions.close();
  }
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test');

  final List<int> audioFetchReelIds = [];
  final List<int> verseFetchReelIds = [];
  int fetchAudioCallCount = 0;
  int fetchReelsCallCount = 0;
  ReelFeed? nextPage;

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    fetchReelsCallCount += 1;
    if (cursor != null && nextPage != null) {
      return nextPage!;
    }
    return const ReelFeed(items: [], nextCursor: null);
  }

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    fetchAudioCallCount += 1;
    audioFetchReelIds.add(reel.id);
    return BibleAudio(
      reference: reel.reference,
      versionId: versionId,
      audioUrl: 'https://cdn.example.org/reel-${reel.id}.mp3',
      startVerse: reel.startVerse,
      endVerse: reel.endVerse,
      verses: [
        BibleAudioVerseTiming(
          verse: reel.startVerse,
          startMs: 1000,
          endMs: 2000,
        ),
      ],
    );
  }

  @override
  Future<BibleVerse> fetchVerse({
    required Reel reel,
    required String versionId,
    int? startVerse,
    int? endVerse,
  }) async {
    verseFetchReelIds.add(reel.id);
    final start = startVerse ?? reel.startVerse;
    return BibleVerse(
      reference: reel.reference,
      versionId: versionId,
      text: 'text for ${reel.id} v$start',
    );
  }
}

Future<void> _pollUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final end = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('pollUntil timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlayer player;
  late _FakeApi api;
  late ReelsController controller;

  setUp(() {
    player = _FakePlayer();
    api = _FakeApi();
    controller = ReelsController(
      api: api,
      storage: _FakeStorage(),
      audioPlayer: player,
    )..autoplayVoice = false;
  });

  tearDown(() async {
    controller.dispose();
  });

  test(
    'prefetches verse text and audio meta for next 10 reels when one becomes visible',
    () async {
      final items = [for (var id = 1; id <= 12; id++) _reel(id)];
      controller.debugSeedFeed(items);

      await controller.onReelVisible(0);
      await _pollUntil(
        () => api.audioFetchReelIds.toSet().containsAll(
              List.generate(10, (i) => i + 1),
            ),
      );

      final prefetchedAudio = api.audioFetchReelIds.toSet();
      expect(prefetchedAudio.containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), isTrue);
      expect(prefetchedAudio.contains(11), isFalse);
      expect(prefetchedAudio.contains(12), isFalse);

      final prefetchedVerses = api.verseFetchReelIds.toSet();
      expect(prefetchedVerses.containsAll([2, 3, 4, 5, 6, 7, 8, 9, 10]), isTrue);

      // Prefetch must not bind audio into the player.
      expect(player.setUrlCallCount, 0);
    },
  );

  test(
    'reuses prefetched audio meta when voiceover starts without refetching',
    () async {
      controller.autoplayVoice = false;
      controller.debugSeedFeed([_reel(1), _reel(2)]);

      await controller.onReelVisible(0);
      await _pollUntil(() => api.audioFetchReelIds.contains(1));
      final audioFetchesAfterPrefetch = api.fetchAudioCallCount;
      expect(player.setUrlCallCount, 0);

      await controller.playVoiceover(_reel(1));
      expect(api.fetchAudioCallCount, audioFetchesAfterPrefetch);
      expect(player.setUrlCallCount, 1);
      expect(player.url, 'https://cdn.example.org/reel-1.mp3');
      expect(player.playing, isTrue);
    },
  );

  test(
    'prefetches verse and audio meta for newly loaded page when near end',
    () async {
      final firstPage = [for (var id = 1; id <= 10; id++) _reel(id)];
      final secondPage = [for (var id = 11; id <= 20; id++) _reel(id)];
      api.nextPage = ReelFeed(
        items: secondPage,
        nextCursor: null,
      );
      controller.debugSeedFeed(firstPage, nextCursor: 10);

      await controller.onReelVisible(8);
      await _pollUntil(() => controller.reels.length == 20);
      await _pollUntil(
        () => api.audioFetchReelIds.toSet().containsAll(
              List.generate(10, (i) => i + 11),
            ),
      );

      expect(api.fetchReelsCallCount, 1);
      final audioIds = api.audioFetchReelIds.toSet();
      expect(audioIds.containsAll([11, 12, 13, 14, 15, 16, 17, 18, 19, 20]), isTrue);
    },
  );
}
