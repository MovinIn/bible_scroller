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
    imageUrl: 'https://cdn.example.com/$id.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

class _FakeStorage extends StorageService {
  @override
  Future<String> readTranslationVersion({String fallback = 'esv'}) async =>
      'esv';

  @override
  Future<void> saveTranslationVersion(String versionId) async {}

  @override
  Future<bool> readAutoplayVoice({bool fallback = true}) async => true;

  @override
  Future<void> saveAutoplayVoice(bool enabled) async {}

  @override
  Future<bool> readVoiceMuted({bool fallback = false}) async => false;

  @override
  Future<void> saveVoiceMuted(bool muted) async {}

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

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test');

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
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
    return BibleVerse(
      reference: reel.reference,
      versionId: versionId,
      text: 'Verse ${reel.startVerse}',
    );
  }
}

class _FakePlayer implements VoiceAudioPlayer {
  final _positions = StreamController<Duration>.broadcast();
  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  int playCallCount = 0;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _state;

  @override
  Future<Duration?> setUrl(String url) async => const Duration(minutes: 3);

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> play() async {
    playCallCount += 1;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlayer player;
  final first = _reel(1);
  final second = _reel(2);

  ReelsController buildController({required bool isWeb}) {
    player = _FakePlayer();
    return ReelsController(
      api: _FakeApi(),
      storage: _FakeStorage(),
      audioPlayer: player,
      isWeb: isWeb,
    )..autoplayVoice = true;
  }

  test('shows click-to-start and stays paused on first visible reel when web',
      () async {
    final controller = buildController(isWeb: true);
    addTearDown(controller.dispose);
    controller.debugSeedFeed([first, second]);

    await controller.onReelVisible(0);
    await pumpEventQueue();

    expect(controller.showClickToStart, isTrue);
    expect(player.playing, isFalse);
    expect(player.playCallCount, 0);
  });

  test('keeps audio paused when scrolling before click-to-start on web', () async {
    final controller = buildController(isWeb: true);
    addTearDown(controller.dispose);
    controller.debugSeedFeed([first, second]);

    await controller.onReelVisible(0);
    await pumpEventQueue();
    await controller.onReelVisible(1);
    await pumpEventQueue();

    expect(controller.showClickToStart, isTrue);
    expect(player.playing, isFalse);
    expect(player.playCallCount, 0);
    expect(controller.currentIndex, 1);
  });

  test('starts current reel audio and hides splash when click-to-start runs on web',
      () async {
    final controller = buildController(isWeb: true);
    addTearDown(controller.dispose);
    controller.debugSeedFeed([first, second]);

    await controller.onReelVisible(0);
    await pumpEventQueue();
    await controller.onReelVisible(1);
    await pumpEventQueue();
    expect(controller.showClickToStart, isTrue);

    await controller.startFromClickToStart();

    expect(controller.showClickToStart, isFalse);
    expect(player.playing, isTrue);
    expect(player.playCallCount, 1);
    expect(controller.isVoiceoverFor(second), isTrue);
  });

  test('does not show click-to-start and autoplays when not web', () async {
    final controller = buildController(isWeb: false);
    addTearDown(controller.dispose);
    controller.debugSeedFeed([first]);

    await controller.onReelVisible(0);
    await pumpEventQueue();

    expect(controller.showClickToStart, isFalse);
    expect(player.playing, isTrue);
    expect(player.playCallCount, 1);
  });

  test('autoplays on scroll after click-to-start has unlocked web audio', () async {
    final controller = buildController(isWeb: true);
    addTearDown(controller.dispose);
    controller.debugSeedFeed([first, second]);

    await controller.onReelVisible(0);
    await pumpEventQueue();
    await controller.startFromClickToStart();
    expect(player.playing, isTrue);

    await controller.onReelVisible(1);
    await pumpEventQueue();

    expect(controller.showClickToStart, isFalse);
    expect(player.playing, isTrue);
    expect(controller.isVoiceoverFor(second), isTrue);
    expect(player.playCallCount, greaterThanOrEqualTo(2));
  });
}
