import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:bible_scroller/audio/voice_audio_player.dart';
import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';
import 'package:bible_scroller/utils/voiceover_presentation.dart';

Reel _reel() {
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
  _FakeApi({this.audio}) : super(deviceId: 'test');

  BibleAudio? audio;
  final Map<String, String> verseTexts = {
    '16-17': 'Full section text for 16-17.',
    '16-16': 'For God so loved the world.',
    '17-17': 'For God did not send his Son.',
  };

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    return audio ??
        const BibleAudio(
          reference: 'John 3:16-17',
          versionId: 'esv',
          audioUrl: '',
          verses: [],
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
    final text = verseTexts['$start-$end'] ?? 'verse $start';
    return BibleVerse(
      reference: 'John 3:$start',
      versionId: versionId,
      text: text,
    );
  }
}

class _FakePlayer implements VoiceAudioPlayer {
  final _positions = StreamController<Duration>.broadcast();
  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  Duration position = Duration.zero;
  final List<Duration> seeks = [];
  String? url;

  void emitPosition(Duration value) {
    position = value;
    _positions.add(value);
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _state;

  @override
  Future<Duration?> setUrl(String url) async {
    this.url = url;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    this.position = position;
  }

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
  Future<void> dispose() async {
    await _positions.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlayer player;
  late _FakeApi api;
  late ReelsController controller;
  final reel = _reel();

  setUp(() {
    player = _FakePlayer();
    api = _FakeApi(
      audio: const BibleAudio(
        reference: 'John 3:16-17',
        versionId: 'esv',
        audioUrl: 'https://cdn.example.org/jhn3.mp3',
        startVerse: 16,
        endVerse: 17,
        verses: [
          BibleAudioVerseTiming(verse: 16, startMs: 45200, endMs: 52100),
          BibleAudioVerseTiming(verse: 17, startMs: 52100, endMs: 59800),
        ],
      ),
    );
    controller = ReelsController(
      api: api,
      storage: _FakeStorage(),
      audioPlayer: player,
    );
  });

  tearDown(() async {
    controller.dispose();
  });

  test('seeks to first verse start_ms when voiceover starts', () async {
    await controller.playVoiceover(reel);

    expect(player.url, 'https://cdn.example.org/jhn3.mp3');
    expect(player.seeks, [const Duration(milliseconds: 45200)]);
    expect(controller.voiceoverPresentation, VoiceoverPresentation.playingActiveVerse);
    expect(controller.activeVerseNumber, 16);
    expect(controller.displayVerseTextFor(reel), 'For God so loved the world.');
  });

  test('advances active verse when position crosses next timestamp', () async {
    await controller.playVoiceover(reel);
    player.emitPosition(const Duration(milliseconds: 52100));
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeVerseNumber, 17);
    expect(
      controller.displayVerseTextFor(reel),
      'For God did not send his Son.',
    );
  });

  test('reveals full section when position reaches section end', () async {
    await controller.playVoiceover(reel);
    player.emitPosition(const Duration(milliseconds: 59800));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.voiceoverPresentation, VoiceoverPresentation.sectionReveal);
    expect(controller.displayVerseTextFor(reel), 'Full section text for 16-17.');
  });

  test('throws when audio timings are empty', () async {
    api.audio = const BibleAudio(
      reference: 'John 3:16-17',
      versionId: 'esv',
      audioUrl: 'https://cdn.example.org/jhn3.mp3',
      verses: [],
    );

    await expectLater(
      controller.playVoiceover(reel),
      throwsA(isA<StateError>()),
    );
    expect(controller.voiceoverPresentation, VoiceoverPresentation.sectionIdle);
  });

  test('stops voiceover when another reel becomes visible with autoplay off', () async {
    controller.autoplayVoice = false;
    await controller.playVoiceover(reel);
    expect(player.playing, isTrue);

    // Simulate feed containing this reel then scrolling away.
    // ignore: invalid_use_of_visible_for_testing_member
    controller.debugSeedFeed([reel, _reelTwo()]);
    await controller.onReelVisible(1);
    await Future<void>.delayed(Duration.zero);

    expect(player.playing, isFalse);
    expect(controller.isVoiceoverFor(reel), isFalse);
  });

  test('finishes clip only once when many positions arrive past end', () async {
    await controller.playVoiceover(reel);
    var reveals = 0;
    controller.addListener(() {
      if (controller.voiceoverPresentation == VoiceoverPresentation.sectionReveal) {
        reveals += 1;
      }
    });

    player.emitPosition(const Duration(milliseconds: 59800));
    player.emitPosition(const Duration(milliseconds: 60000));
    player.emitPosition(const Duration(milliseconds: 62000));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(reveals, 1);
    expect(controller.voiceoverPresentation, VoiceoverPresentation.sectionReveal);
  });
}

Reel _reelTwo() {
  return Reel(
    id: 2,
    reference: 'John 3:18',
    book: 'John',
    chapter: 3,
    startVerse: 18,
    endVerse: 18,
    slug: 'John_3_18-18',
    imageUrl: 'https://cdn.example.com/2.png',
    iqBookId: '43',
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
  );
}
