import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_scroller/audio/voice_audio_player.dart';
import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.audio}) : super(deviceId: 'test-device');

  final BibleAudio? audio;

  @override
  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    return const ReelFeed(items: [], nextCursor: null);
  }

  @override
  Future<List<String>> fetchBooks() async => const [];

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    return const [
      BibleVersion(versionId: 'niv', name: 'New International Version'),
    ];
  }

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    return audio ??
        const BibleAudio(
          reference: 'John 3:16-17',
          versionId: 'esv',
          audioUrl: 'https://cdn.example.org/jhn3.mp3',
          startVerse: 16,
          endVerse: 17,
          verses: [
            BibleAudioVerseTiming(verse: 16, startMs: 45200, endMs: 52100),
            BibleAudioVerseTiming(verse: 17, startMs: 52100, endMs: 59800),
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
    final start = startVerse ?? reel.startVerse;
    final end = endVerse ?? reel.endVerse;
    final text = start == end && start == 16
        ? 'For God so loved the world.'
        : start == end && start == 17
            ? 'For God did not send his Son.'
            : 'Full section text for 16-17.';
    return BibleVerse(
      reference: 'John 3:$start',
      versionId: versionId,
      text: text,
    );
  }
}

class _FakePlayer implements VoiceAudioPlayer {
  final _positions = StreamController<Duration>.broadcast();
  double speed = 1.0;
  final List<double> setSpeedCalls = [];
  Duration position = Duration.zero;

  void emitPosition(Duration value) {
    position = value;
    _positions.add(value);
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  bool get playing => false;

  @override
  ProcessingState get processingState => ProcessingState.idle;

  @override
  Future<Duration?> setUrl(String url) async => const Duration(minutes: 3);

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
    setSpeedCalls.add(speed);
  }

  @override
  Future<void> dispose() async {
    await _positions.close();
  }
}

Reel _speedReel() {
  return Reel(
    id: 1,
    reference: 'John 3:16-17',
    book: 'John',
    chapter: 3,
    startVerse: 16,
    endVerse: 17,
    slug: 'John_3_16-17',
    imageUrl: 'https://cdn.example.com/1.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;
  late _FakePlayer player;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_speed_');
    SharedPreferences.setMockInitialValues({});
    Hive.init(tempDir.path);
    storage = StorageService();
    await storage.init(hivePath: tempDir.path);
    player = _FakePlayer();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('voicePlaybackSpeed is 1.0 when preference is not stored', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );

    await controller.initialize();

    expect(controller.voicePlaybackSpeed, 1.0);
  });

  test('voicePlaybackSpeed matches stored preference on initialize', () async {
    await storage.saveVoicePlaybackSpeed(1.75);
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );

    await controller.initialize();

    expect(controller.voicePlaybackSpeed, 1.75);
  });

  test('setVoicePlaybackSpeed updates voicePlaybackSpeed to requested value', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();

    await controller.setVoicePlaybackSpeed(1.5);

    expect(controller.voicePlaybackSpeed, 1.5);
  });

  test('setVoicePlaybackSpeed persists preference', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();

    await controller.setVoicePlaybackSpeed(0.75);

    expect(await storage.readVoicePlaybackSpeed(), 0.75);
  });

  test('setVoicePlaybackSpeed applies speed to audio player', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();

    await controller.setVoicePlaybackSpeed(2.0);

    expect(player.setSpeedCalls, [2.0]);
  });

  test('setVoicePlaybackSpeed skips persistence when persist is false', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();

    await controller.setVoicePlaybackSpeed(1.5, persist: false);

    expect(controller.voicePlaybackSpeed, 1.5);
    expect(player.setSpeedCalls, [1.5]);
    expect(await storage.readVoicePlaybackSpeed(), 1.0);
  });

  test('setVoicePlaybackSpeed persists when persist is true after a non-persisting change',
      () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();
    await controller.setVoicePlaybackSpeed(1.5, persist: false);

    await controller.setVoicePlaybackSpeed(1.5, persist: true);

    expect(await storage.readVoicePlaybackSpeed(), 1.5);
  });

  test('setVoicePlaybackSpeed clamps below minimum to 0.5', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();

    await controller.setVoicePlaybackSpeed(0.25);

    expect(controller.voicePlaybackSpeed, 0.5);
    expect(await storage.readVoicePlaybackSpeed(), 0.5);
  });

  test('setVoicePlaybackSpeed clamps above maximum to 2.0', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();

    await controller.setVoicePlaybackSpeed(4.0);

    expect(controller.voicePlaybackSpeed, 2.0);
    expect(await storage.readVoicePlaybackSpeed(), 2.0);
  });

  test('playVoiceover applies stored playback speed to audio player', () async {
    await storage.saveVoicePlaybackSpeed(1.5);
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();
    player.setSpeedCalls.clear();

    await controller.playVoiceover(_speedReel());

    expect(player.setSpeedCalls, [1.5]);
  });

  test('advances active verse at 2x when position crosses next timestamp', () async {
    final controller = ReelsController(
      api: _FakeApi(),
      storage: storage,
      audioPlayer: player,
    );
    await controller.initialize();
    await controller.setVoicePlaybackSpeed(2.0);
    final reel = _speedReel();

    await controller.playVoiceover(reel);
    player.emitPosition(const Duration(milliseconds: 52100));
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeVerseNumber, 17);
    expect(
      controller.displayVerseTextFor(reel),
      'For God did not send his Son.',
    );
  });
}
