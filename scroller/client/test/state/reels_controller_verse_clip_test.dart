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
  Future<void>? delayAudio;
  Future<void>? delayVerse;
  /// When set, only delays audio for this reel id (others resolve immediately).
  int? delayAudioForReelId;
  Completer<void>? verseFetchStarted;
  Completer<void>? audioFetchStarted;
  final List<int> audioFetchReelIds = [];
  final List<int> verseFetchReelIds = [];
  int fetchAudioCallCount = 0;
  int fetchVerseCallCount = 0;
  final Map<String, String> verseTexts = {
    '16-17': 'Full section text for 16-17.',
    '16-16': 'For God so loved the world.',
    '17-17': 'For God did not send his Son.',
    '18-18': 'verse 18',
  };

  @override
  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    fetchAudioCallCount += 1;
    audioFetchReelIds.add(reel.id);
    final delay = delayAudio;
    final shouldDelay =
        delay != null &&
        (delayAudioForReelId == null || delayAudioForReelId == reel.id);
    final started = audioFetchStarted;
    if (shouldDelay && started != null && !started.isCompleted) {
      started.complete();
    }
    if (shouldDelay) {
      await delay;
    }
    if (audio != null && reel.id == 1) {
      return audio!;
    }
    return BibleAudio(
      reference: reel.reference,
      versionId: 'esv',
      audioUrl: 'https://cdn.example.org/reel-${reel.id}.mp3',
      startVerse: reel.startVerse,
      endVerse: reel.endVerse,
      verses: [
        for (var v = reel.startVerse; v <= reel.endVerse; v++)
          BibleAudioVerseTiming(
            verse: v,
            startMs: v * 1000,
            endMs: (v + 1) * 1000,
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
    fetchVerseCallCount += 1;
    verseFetchReelIds.add(reel.id);
    final started = verseFetchStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final delay = delayVerse;
    if (delay != null) {
      await delay;
    }
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
  final List<String> setUrlCalls = [];
  String? url;
  bool throwOnPlay = false;
  int playCallCount = 0;
  int stopCallCount = 0;
  Future<void>? delaySetUrl;
  String? delaySetUrlForUrl;
  Completer<void>? setUrlStarted;

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
    setUrlCalls.add(url);
    final shouldDelay = delaySetUrl != null &&
        (delaySetUrlForUrl == null || delaySetUrlForUrl == url);
    if (shouldDelay) {
      final started = setUrlStarted;
      if (started != null && !started.isCompleted) {
        started.complete();
      }
      await delaySetUrl;
    }
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
    playCallCount += 1;
    if (throwOnPlay) {
      throw StateError('autoplay blocked');
    }
    _playing = true;
    _state = ProcessingState.ready;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
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

Future<void> _waitUntil(
  ReelsController controller,
  bool Function() predicate,
) async {
  if (predicate()) {
    return;
  }
  final done = Completer<void>();
  void listener() {
    if (predicate() && !done.isCompleted) {
      done.complete();
    }
  }

  controller.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 2));
  } finally {
    controller.removeListener(listener);
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

  test('keeps playing when same reel becomes visible again', () async {
    controller.autoplayVoice = true;
    controller.debugSeedFeed([reel, _reelTwo()]);
    await controller.onReelVisible(0);
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isTrue);
    final playsAfterFirst = player.playCallCount;

    await controller.onReelVisible(0);
    await Future<void>.delayed(Duration.zero);

    expect(player.playing, isTrue);
    expect(player.playCallCount, playsAfterFirst);
    expect(controller.isVoiceoverFor(reel), isTrue);
  });

  test('notifies and shows verse text when play is blocked after setup', () async {
    player.throwOnPlay = true;
    controller.debugSeedFeed([reel]);

    await expectLater(controller.playVoiceover(reel), throwsA(isA<StateError>()));

    expect(controller.verseTextFor(reel), 'Full section text for 16-17.');
    expect(controller.voiceoverPresentation, VoiceoverPresentation.playingActiveVerse);
    expect(controller.activeVerseNumber, 16);
  });

  test('loads next reel verse text when scrolling with autoplay on', () async {
    controller.autoplayVoice = true;
    controller.debugSeedFeed([reel, _reelTwo()]);
    await controller.onReelVisible(0);
    await Future<void>.delayed(Duration.zero);

    await controller.onReelVisible(1);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.verseTextFor(_reelTwo()),
      isNot(contains('Loading')),
    );
    expect(controller.verseTextFor(_reelTwo()), 'verse 18');
  });

  test('shows first verse chunk while autoplay audio is still loading after scroll',
      () async {
    final audioGate = Completer<void>();
    api.delayAudio = audioGate.future;
    controller.autoplayVoice = true;
    controller.debugSeedFeed([reel]);

    final displayed = <String>[];
    controller.addListener(() {
      displayed.add(controller.displayVerseTextFor(reel));
    });

    final visible = controller.onReelVisible(0);

    await _waitUntil(
      controller,
      () =>
          controller.voiceoverPresentation ==
              VoiceoverPresentation.playingActiveVerse &&
          controller.activeVerseTextFor(reel) != null,
    );

    expect(
      controller.voiceoverPresentation,
      VoiceoverPresentation.playingActiveVerse,
    );
    expect(controller.activeVerseNumber, 16);
    expect(
      controller.displayVerseTextFor(reel),
      'For God so loved the world.',
    );
    expect(player.playing, isFalse);

    audioGate.complete();
    await visible;

    expect(player.playing, isTrue);
    expect(
      controller.displayVerseTextFor(reel),
      'For God so loved the world.',
    );
    expect(
      displayed.where((text) => text == 'Full section text for 16-17.'),
      isEmpty,
    );
  });

  test('shows next reel first verse chunk while its autoplay audio is loading',
      () async {
    controller.autoplayVoice = true;
    controller.debugSeedFeed([reel, _reelTwo()]);
    await controller.onReelVisible(0);
    await Future<void>.delayed(Duration.zero);

    final audioGate = Completer<void>();
    api.delayAudio = audioGate.future;
    final visible = controller.onReelVisible(1);

    await _waitUntil(
      controller,
      () =>
          controller.isVoiceoverFor(_reelTwo()) &&
          controller.voiceoverPresentation ==
              VoiceoverPresentation.playingActiveVerse,
    );

    expect(controller.isVoiceoverFor(_reelTwo()), isTrue);
    expect(
      controller.voiceoverPresentation,
      VoiceoverPresentation.playingActiveVerse,
    );
    expect(
      controller.displayVerseTextFor(_reelTwo()),
      'verse 18',
    );

    audioGate.complete();
    await visible;
  });

  test('starts voiceover when same reel becomes visible twice before audio loads',
      () async {
    final verseStarted = Completer<void>();
    final verseGate = Completer<void>();
    final audioGate = Completer<void>();
    api.verseFetchStarted = verseStarted;
    api.delayVerse = verseGate.future;
    api.delayAudio = audioGate.future;
    controller.autoplayVoice = true;
    controller.debugSeedFeed([reel]);

    final first = controller.onReelVisible(0);
    await verseStarted.future;

    // Supersede while Gen1 is inside _beginActiveVersePresentation.
    final second = controller.onReelVisible(0);

    verseGate.complete();
    audioGate.complete();
    await Future.wait([first, second]);

    expect(player.playing, isTrue);
    expect(player.playCallCount, greaterThanOrEqualTo(1));
    expect(
      controller.displayVerseTextFor(reel),
      'For God so loved the world.',
    );
  });

  test(
    'shows next reel first verse chunk while previous reel audio is still loading',
    () async {
      final audioGate = Completer<void>();
      final audioStarted = Completer<void>();
      api.delayAudio = audioGate.future;
      api.delayAudioForReelId = 1;
      api.audioFetchStarted = audioStarted;
      controller.autoplayVoice = true;
      controller.debugSeedFeed([reel, _reelTwo()]);

      unawaited(controller.onReelVisible(0));
      await audioStarted.future;

      final nextVisible = controller.onReelVisible(1);
      await _pollUntil(
        () =>
            controller.isVoiceoverFor(_reelTwo()) &&
            controller.displayVerseTextFor(_reelTwo()) == 'verse 18' &&
            api.audioFetchReelIds.contains(2),
      );

      expect(controller.isVoiceoverFor(_reelTwo()), isTrue);
      expect(
        controller.displayVerseTextFor(_reelTwo()),
        'verse 18',
      );
      // Next reel must start its own audio fetch before prior gate opens.
      expect(api.audioFetchReelIds, contains(2));
      expect(audioGate.isCompleted, isFalse);

      audioGate.complete();
      await nextVisible;
    },
  );

  test(
    'does not leave previous reel playing when its audio finishes after scroll away',
    () async {
      final audioGate = Completer<void>();
      final audioStarted = Completer<void>();
      api.delayAudio = audioGate.future;
      api.delayAudioForReelId = 1;
      api.audioFetchStarted = audioStarted;
      controller.autoplayVoice = true;
      controller.debugSeedFeed([reel, _reelTwo()]);

      unawaited(controller.onReelVisible(0));
      await audioStarted.future;

      final nextVisible = controller.onReelVisible(1);
      await _pollUntil(
        () =>
            controller.isVoiceoverFor(_reelTwo()) &&
            controller.displayVerseTextFor(_reelTwo()) == 'verse 18' &&
            api.audioFetchReelIds.contains(2),
      );

      expect(audioGate.isCompleted, isFalse);
      audioGate.complete();
      await nextVisible;

      expect(controller.isVoiceoverFor(reel), isFalse);
      expect(controller.isVoiceoverFor(_reelTwo()), isTrue);
      expect(player.playing, isTrue);
      expect(player.url, 'https://cdn.example.org/reel-2.mp3');
    },
  );

  test(
    'keeps next reel audio bound when previous setUrl finishes after scroll away',
    () async {
      final setUrlGate = Completer<void>();
      final setUrlStarted = Completer<void>();
      player.delaySetUrl = setUrlGate.future;
      player.delaySetUrlForUrl = 'https://cdn.example.org/jhn3.mp3';
      player.setUrlStarted = setUrlStarted;
      controller.autoplayVoice = true;
      controller.debugSeedFeed([reel, _reelTwo()]);

      unawaited(controller.onReelVisible(0));
      await setUrlStarted.future;

      final nextVisible = controller.onReelVisible(1);
      await _pollUntil(
        () =>
            controller.isVoiceoverFor(_reelTwo()) &&
            player.playing &&
            player.url == 'https://cdn.example.org/reel-2.mp3',
      );

      expect(setUrlGate.isCompleted, isFalse);
      setUrlGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await nextVisible;

      expect(controller.isVoiceoverFor(_reelTwo()), isTrue);
      expect(player.playing, isTrue);
      expect(player.url, 'https://cdn.example.org/reel-2.mp3');
      expect(player.setUrlCalls, contains('https://cdn.example.org/jhn3.mp3'));
      expect(player.setUrlCalls, contains('https://cdn.example.org/reel-2.mp3'));
    },
  );

  test('does not stop voiceover again during playVoiceover after early begin',
      () async {
    final audioGate = Completer<void>();
    api.delayAudio = audioGate.future;
    controller.autoplayVoice = true;
    controller.debugSeedFeed([reel]);

    final visible = controller.onReelVisible(0);
    await _waitUntil(
      controller,
      () => controller.activeVerseTextFor(reel) != null,
    );

    final stopsAfterBegin = player.stopCallCount;
    audioGate.complete();
    await visible;

    expect(player.stopCallCount, stopsAfterBegin);
    expect(player.playing, isTrue);
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
