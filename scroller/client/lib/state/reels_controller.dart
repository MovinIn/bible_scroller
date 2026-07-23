import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/voice_audio_player.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/position_cookie.dart';
import '../services/storage_service.dart';
import '../utils/startup_timing.dart';
import '../utils/verse_audio_timing.dart';
import '../utils/verse_cache_policy.dart';
import '../utils/voiceover_presentation.dart';
import '../utils/voiceover_tap_action.dart';

class ReelsController extends ChangeNotifier {
  ReelsController({
    required ApiClient api,
    required StorageService storage,
    VoiceAudioPlayer? audioPlayer,
    bool? isWeb,
  })  : _api = api,
        _storage = storage,
        _audioPlayerOverride = audioPlayer,
        _isWeb = isWeb ?? kIsWeb;

  final ApiClient _api;
  final StorageService _storage;
  final VoiceAudioPlayer? _audioPlayerOverride;
  VoiceAudioPlayer? _lazyAudioPlayer;
  final bool _isWeb;
  /// After the user dismisses web click-to-start, autoplay-on-visible resumes.
  bool _webAudioStarted = false;

  static const int _prefetchBatchSize = 10;

  final List<Reel> _reels = [];
  final Map<int, String> _verseTextByReelId = {};
  /// Per-verse text: key = "$reelId:$verse".
  final Map<String, String> _verseTextByReelVerse = {};
  final Map<int, BibleAudio> _audioByReelId = {};
  final Map<int, Future<void>> _verseTextInFlight = {};
  final Map<int, Future<BibleAudio>> _audioMetaInFlight = {};
  final Map<int, List<Comment>> _commentsByReelId = {};
  bool _disposed = false;
  int _translationEpoch = 0;

  bool loading = true;
  bool loadingMore = false;
  bool loadingPrevious = false;
  String? error;
  String translationVersion = 'esv';
  bool autoplayVoice = true;
  bool isMuted = false;
  double voicePlaybackSpeed = StorageService.defaultVoicePlaybackSpeed;
  bool discoveryMode = false;
  bool defineModeEnabled = false;
  List<BibleVersion> versions = const [];
  List<String> books = const [];
  int? _nextCursor;
  int? _prevCursor;
  int _currentIndex = 0;
  int? _voiceoverReelId;
  VoiceoverPresentation voiceoverPresentation = VoiceoverPresentation.sectionIdle;
  int? activeVerseNumber;
  List<BibleAudioVerseTiming> _clipVerses = const [];
  StreamSubscription<Duration>? _positionSub;
  bool _clipFinishing = false;
  Future<void>? _booksLoadFuture;
  Future<void>? _versionsLoadFuture;
  int _visibleWorkGeneration = 0;
  /// Bumped on stop / each new playVoiceover bind so superseded work cannot
  /// mutate the shared player or `_clipVerses`.
  int _playbackEpoch = 0;
  /// URL the current playback epoch intends to keep bound (for late setUrl restore).
  String? _activeBindUrl;
  int _activeBindEpoch = 0;
  final Map<int, WordStudy> _wordStudyByReelId = {};

  List<Reel> get reels => List.unmodifiable(_reels);
  int get currentIndex => _currentIndex;
  Reel? get currentReel => _reels.isEmpty ? null : _reels[_currentIndex];
  bool get canLoadNext => _nextCursor != null;
  bool get canLoadPrevious => _prevCursor != null;

  /// Web-only: wait for an explicit click before any audible playback.
  bool get showClickToStart =>
      _isWeb && !_webAudioStarted && autoplayVoice;

  bool isVoiceoverFor(Reel reel) => _voiceoverReelId == reel.id;

  /// Test-only: seed voiceover presentation without playing audio.
  @visibleForTesting
  void debugSeedVoiceover({
    required int reelId,
    required VoiceoverPresentation presentation,
    int? activeVerse,
    String? sectionText,
    Map<int, String>? perVerseText,
  }) {
    _voiceoverReelId = reelId;
    voiceoverPresentation = presentation;
    activeVerseNumber = activeVerse;
    if (sectionText != null) {
      _verseTextByReelId[reelId] = sectionText;
    }
    perVerseText?.forEach((verse, text) {
      _verseTextByReelVerse[_verseKey(reelId, verse)] = text;
    });
    notifyListeners();
  }

  /// Test-only: replace in-memory feed items.
  @visibleForTesting
  void debugSeedFeed(List<Reel> items, {int? nextCursor}) {
    _reels
      ..clear()
      ..addAll(items);
    _nextCursor = nextCursor;
    notifyListeners();
  }

  VoiceAudioPlayer get _audioPlayer {
    if (_audioPlayerOverride != null) {
      return _audioPlayerOverride!;
    }
    return _lazyAudioPlayer ??= JustAudioVoicePlayer();
  }

  Future<void> initialize() async {
    await StartupTiming.track('init.prefs', () async {
      translationVersion = await _storage.readTranslationVersion();
      autoplayVoice = await _storage.readAutoplayVoice();
      isMuted = await _storage.readVoiceMuted();
      voicePlaybackSpeed = await _storage.readVoicePlaybackSpeed();
      discoveryMode = await _storage.readDiscoveryMode();
    });
    await StartupTiming.track('init.refreshFeed', refreshFeed);
  }

  Future<void> ensureBooksLoaded() async {
    if (books.isNotEmpty) {
      return;
    }
    final inFlight = _booksLoadFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final load = _loadBooks();
    _booksLoadFuture = load;
    try {
      await load;
    } finally {
      if (identical(_booksLoadFuture, load)) {
        _booksLoadFuture = null;
      }
    }
  }

  Future<void> ensureVersionsLoaded() async {
    if (versions.isNotEmpty) {
      return;
    }
    final inFlight = _versionsLoadFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final load = _loadVersions();
    _versionsLoadFuture = load;
    try {
      await load;
    } finally {
      if (identical(_versionsLoadFuture, load)) {
        _versionsLoadFuture = null;
      }
    }
  }

  Future<void> _loadVersions() async {
    try {
      versions = await _api.fetchVersions();
      notifyListeners();
    } catch (_) {
      versions = const [
        BibleVersion(versionId: 'esv', name: 'English Standard Version'),
        BibleVersion(versionId: 'kjv', name: 'King James Version'),
        BibleVersion(versionId: 'web', name: 'World English Bible'),
        BibleVersion(versionId: 'nkjv', name: 'New King James Version'),
        BibleVersion(versionId: 'nasb', name: 'New American Standard Bible'),
        BibleVersion(versionId: 'nlt', name: 'New Living Translation'),
        BibleVersion(versionId: 'nlh', name: 'New Living Translation (her.BIBLE)'),
        BibleVersion(versionId: 'asv', name: 'American Standard Version'),
        BibleVersion(versionId: 'evd', name: 'English Version for the Deaf'),
        BibleVersion(versionId: 'rev', name: 'Revised Version 1885'),
        BibleVersion(versionId: 'nlv', name: 'New Life Version'),
      ];
    }
  }

  Future<void> _loadBooks() async {
    try {
      books = await _api.fetchBooks();
      notifyListeners();
    } catch (_) {
      books = const [];
    }
  }

  /// Jump the feed to the first reel of [book]. Returns page index 0 on
  /// success, or null when the book has no reels (feed left unchanged).
  Future<int?> jumpToBook(String book) async {
    try {
      await _exitDiscoveryModeIfNeeded();
      return await _replaceFeedWith(
        () => _api.fetchReels(limit: 10, book: book),
      );
    } catch (_) {
      return null;
    }
  }

  /// Jump the feed to [reelId] (a verse section). Returns page index 0 on
  /// success, or null when no reels start at that id (feed left unchanged).
  Future<int?> jumpToSection(int reelId) async {
    try {
      await _exitDiscoveryModeIfNeeded();
      return await _replaceFeedWith(
        () => _api.fetchReels(limit: 10, fromId: reelId),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _exitDiscoveryModeIfNeeded() async {
    if (!discoveryMode) {
      return;
    }
    discoveryMode = false;
    await _storage.saveDiscoveryMode(false);
  }

  void _clearContentCaches() {
    _verseTextByReelId.clear();
    _verseTextByReelVerse.clear();
    _audioByReelId.clear();
    _verseTextInFlight.clear();
    _audioMetaInFlight.clear();
  }

  void _pruneContentCachesToFeed() {
    final ids = _reels.map((reel) => reel.id).toSet();
    _verseTextByReelId.removeWhere((id, _) => !ids.contains(id));
    _audioByReelId.removeWhere((id, _) => !ids.contains(id));
    _verseTextByReelVerse.removeWhere((key, _) {
      final reelId = int.tryParse(key.split(':').first);
      return reelId == null || !ids.contains(reelId);
    });
    _verseTextInFlight.removeWhere((id, _) => !ids.contains(id));
    _audioMetaInFlight.removeWhere((id, _) => !ids.contains(id));
  }

  Future<int?> _replaceFeedWith(Future<ReelFeed> Function() fetch) async {
    final feed = await fetch();
    if (feed.items.isEmpty) {
      return null;
    }
    _reels
      ..clear()
      ..addAll(feed.items);
    _nextCursor = feed.nextCursor;
    _prevCursor = feed.prevCursor;
    _currentIndex = 0;
    _pruneContentCachesToFeed();
    notifyListeners();
    unawaited(_scheduleOnReelVisible(0));
    return 0;
  }

  Future<List<int>> fetchChapters(String book) => _api.fetchChapters(book);

  Future<List<VerseSection>> fetchSections({
    required String book,
    required int chapter,
  }) {
    return _api.fetchSections(book: book, chapter: chapter);
  }

  Future<void> refreshFeed() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final ReelFeed feed;
      if (discoveryMode) {
        feed = await StartupTiming.track(
          'feed.fetchDiscoveryReels',
          () => _api.fetchDiscoveryReels(limit: 10),
        );
      } else {
        final resumeId = readLastReelIdFromCookie();
        var sequential = await StartupTiming.track(
          'feed.fetchReels',
          () => _api.fetchReels(limit: 10, fromId: resumeId),
        );
        if (sequential.items.isEmpty && resumeId != null) {
          clearLastReelCookie();
          sequential = await _api.fetchReels(limit: 10);
        }
        feed = sequential;
      }
      _reels
        ..clear()
        ..addAll(feed.items);
      _nextCursor = feed.nextCursor;
      _prevCursor = discoveryMode ? null : feed.prevCursor;
      _pruneContentCachesToFeed();
      loading = false;
      notifyListeners();
      if (_reels.isNotEmpty) {
        unawaited(_scheduleOnReelVisible(0));
      }
    } catch (err) {
      loading = false;
      error = err.toString();
      notifyListeners();
    }
  }

  Future<void> setDiscoveryMode(bool enabled) async {
    if (discoveryMode == enabled) {
      return;
    }
    discoveryMode = enabled;
    await _storage.saveDiscoveryMode(enabled);
    notifyListeners();
    await refreshFeed();
  }

  Future<void> _scheduleOnReelVisible(int index) {
    final generation = ++_visibleWorkGeneration;
    // Do not await prior visibility work — scrolling away must start the next
    // reel immediately while superseded playVoiceover aborts on generation checks.
    return () async {
      if (generation != _visibleWorkGeneration) {
        return;
      }
      await _runOnReelVisible(index, generation);
    }();
  }

  Future<void> _runOnReelVisible(int index, int generation) async {
    if (generation != _visibleWorkGeneration) {
      return;
    }
    if (index < 0 || index >= _reels.length) {
      return;
    }
    final reel = _reels[index];
    // Require a real clip/playback — early chunk presentation alone must not
    // suppress a later playVoiceover when a newer visibility supersedes begin.
    final alreadyPlayingThis = _voiceoverReelId == reel.id &&
        (_audioPlayer.playing || _clipVerses.isNotEmpty);

    // Do not stop/restart when PageView re-notifies the same reel (kills web autoplay).
    if (!alreadyPlayingThis) {
      await stopVoiceover();
      if (!autoplayVoice) {
        notifyListeners();
      }
    }
    if (generation != _visibleWorkGeneration) {
      // Stopped without rebound; push idle so UI does not keep prior chunk text.
      if (autoplayVoice && !alreadyPlayingThis) {
        notifyListeners();
      }
      return;
    }
    if (autoplayVoice && !alreadyPlayingThis) {
      // Show the first verse chunk before audio loads so scroll never flashes
      // the full section text (pause/resume used to be required to recover).
      await _beginActiveVersePresentation(reel);
      if (generation != _visibleWorkGeneration) {
        await stopVoiceover();
        notifyListeners();
        return;
      }
    }
    await StartupTiming.track('reel.loadMoreIfNeeded', () => loadMoreIfNeeded(index));
    if (generation != _visibleWorkGeneration) {
      return;
    }
    // Warm verse text + audio metadata for this window; never block playback.
    unawaited(_prefetchAhead(index));
    if (index < _reels.length) {
      if (!discoveryMode) {
        writeLastReelCookie(_reels[index].id);
      }
    }
    if (!autoplayVoice) {
      return;
    }
    if (alreadyPlayingThis) {
      return;
    }
    // Web: stay paused until the user clicks "Click to start" (scroll must not play).
    if (showClickToStart) {
      notifyListeners();
      return;
    }
    if (defineModeEnabled) {
      await _ensureWordStudy(reel);
    }
    if (generation != _visibleWorkGeneration) {
      return;
    }
    try {
      await StartupTiming.track(
        'reel.playVoiceover',
        () => playVoiceover(reel, visibilityGeneration: generation),
      );
    } catch (_) {
      // Audio may be unavailable (browser autoplay block / missing timings).
      notifyListeners();
    }
  }

  Future<void> onReelVisible(int index) => _scheduleOnReelVisible(index);

  /// Web click-to-start: dismiss the splash and begin audio for the current reel.
  Future<void> startFromClickToStart() async {
    if (!_isWeb || _webAudioStarted) {
      return;
    }
    _webAudioStarted = true;
    notifyListeners();
    if (!autoplayVoice) {
      return;
    }
    final reel = currentReel;
    if (reel == null) {
      return;
    }
    try {
      await playVoiceover(reel);
    } catch (_) {
      notifyListeners();
    }
  }

  Future<void> setAutoplayVoice(bool enabled) async {
    autoplayVoice = enabled;
    await _storage.saveAutoplayVoice(enabled);
    if (!enabled) {
      await stopVoiceover();
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    await _storage.saveVoiceMuted(isMuted);
    await _applyAudioVolume();
    notifyListeners();
  }

  Future<void> setVoicePlaybackSpeed(
    double speed, {
    bool persist = true,
  }) async {
    voicePlaybackSpeed = StorageService.clampVoicePlaybackSpeed(speed);
    if (persist) {
      await _storage.saveVoicePlaybackSpeed(voicePlaybackSpeed);
    }
    await _applyAudioSpeed();
    notifyListeners();
  }

  Future<void> setDefineMode(bool enabled) async {
    defineModeEnabled = enabled;
    notifyListeners();
    if (enabled && currentReel != null) {
      await _ensureWordStudy(currentReel!);
    }
  }

  WordStudy? wordStudyFor(Reel reel) => _wordStudyByReelId[reel.id];

  Future<void> _ensureWordStudy(Reel reel, {bool force = false}) async {
    if (!force && _wordStudyByReelId.containsKey(reel.id)) {
      return;
    }
    try {
      final study = await _api.fetchWordStudy(reel: reel);
      _wordStudyByReelId[reel.id] = study;
      notifyListeners();
    } catch (_) {
      // Define mode stays on; overlay can show empty / keep prior cache.
    }
  }

  Future<void> _applyAudioVolume() async {
    try {
      await _audioPlayer.setVolume(isMuted ? 0.0 : 1.0);
    } catch (_) {
      // Audio player may be unavailable in tests or before first playback.
    }
  }

  Future<void> _applyAudioSpeed() async {
    try {
      await _audioPlayer.setSpeed(voicePlaybackSpeed);
    } catch (_) {
      // Audio player may be unavailable in tests or before first playback.
    }
  }

  Future<void> loadMoreIfNeeded(int index) async {
    _currentIndex = index;
    var appendedFrom = -1;
    if (index >= _reels.length - 2 && _nextCursor != null && !loadingMore) {
      loadingMore = true;
      notifyListeners();
      final useDiscovery = discoveryMode;
      final excludeIds = _reels.map((reel) => reel.id).toList();
      final cursor = _nextCursor;
      try {
        final feed = useDiscovery
            ? await _api.fetchDiscoveryReels(limit: 10, excludeIds: excludeIds)
            : await _api.fetchReels(cursor: cursor, limit: 10);
        appendedFrom = _reels.length;
        _reels.addAll(feed.items);
        _nextCursor = feed.nextCursor;
        if (useDiscovery) {
          _prevCursor = null;
        }
      } catch (_) {
        // Keep already-loaded reels scrollable if pagination fails.
      } finally {
        loadingMore = false;
        notifyListeners();
      }
    }

    if (index < _reels.length) {
      await _ensureVerseText(_reels[index]);
    }
    if (appendedFrom >= 0 && appendedFrom < _reels.length) {
      unawaited(_prefetchAhead(appendedFrom));
    }
  }

  /// Loads the next page when the user is on the last loaded reel.
  Future<bool> ensureNextPageLoaded() async {
    if (_nextCursor == null || loadingMore) {
      return false;
    }

    loadingMore = true;
    notifyListeners();
    final useDiscovery = discoveryMode;
    final excludeIds = _reels.map((reel) => reel.id).toList();
    final cursor = _nextCursor;
    try {
      final feed = useDiscovery
          ? await _api.fetchDiscoveryReels(limit: 10, excludeIds: excludeIds)
          : await _api.fetchReels(cursor: cursor, limit: 10);
      if (feed.items.isEmpty) {
        _nextCursor = null;
        return false;
      }
      final appendedFrom = _reels.length;
      _reels.addAll(feed.items);
      _nextCursor = feed.nextCursor;
      if (useDiscovery) {
        _prevCursor = null;
      }
      unawaited(_prefetchAhead(appendedFrom));
      return true;
    } catch (_) {
      return false;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  /// Prepends earlier reels when the user scrolls up from the first loaded reel.
  /// Returns how many reels were inserted (caller adjusts [PageController]).
  Future<int> prependPreviousPage() async {
    if (discoveryMode || _prevCursor == null || loadingPrevious) {
      return 0;
    }

    loadingPrevious = true;
    notifyListeners();
    try {
      final feed = await _api.fetchReels(beforeId: _prevCursor, limit: 10);
      if (feed.items.isEmpty) {
        _prevCursor = null;
        return 0;
      }
      _reels.insertAll(0, feed.items);
      _prevCursor = feed.prevCursor;
      unawaited(_prefetchAhead(0));
      return feed.items.length;
    } catch (_) {
      return 0;
    } finally {
      loadingPrevious = false;
      notifyListeners();
    }
  }

  Future<void> setTranslation(String versionId) async {
    translationVersion = versionId;
    _translationEpoch++;
    await _storage.saveTranslationVersion(versionId);
    _clearContentCaches();
    notifyListeners();
    if (currentReel != null) {
      await _ensureVerseText(currentReel!, force: true);
    }
  }

  void _notifyIfActive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void> _prefetchAhead(int fromIndex) async {
    if (fromIndex < 0 || fromIndex >= _reels.length) {
      return;
    }
    final end = (fromIndex + _prefetchBatchSize).clamp(0, _reels.length);
    final futures = <Future<void>>[];
    for (var i = fromIndex; i < end; i++) {
      futures.add(_prefetchReelContent(_reels[i]));
    }
    await Future.wait(futures);
  }

  Future<void> _prefetchReelContent(Reel reel) async {
    try {
      await Future.wait([
        _ensureVerseText(reel),
        _ensureAudioMeta(reel),
      ]);
      await _ensurePerVerseTexts(reel);
    } catch (_) {
      // Prefetch is best-effort; visible path will retry.
    }
  }

  Future<BibleAudio> _ensureAudioMeta(Reel reel, {bool force = false}) async {
    if (!force) {
      final cached = _audioByReelId[reel.id];
      if (cached != null) {
        return cached;
      }
      final inFlight = _audioMetaInFlight[reel.id];
      if (inFlight != null) {
        return inFlight;
      }
    }

    final gate = Completer<BibleAudio>();
    _audioMetaInFlight[reel.id] = gate.future;
    final versionId = translationVersion;
    final translationEpoch = _translationEpoch;
    try {
      final audio = await _api.fetchAudio(reel: reel, versionId: versionId);
      if (translationEpoch == _translationEpoch) {
        final playable = isPlayableAudioUrl(audio.audioUrl) &&
            audio.verses.isNotEmpty &&
            sectionStartMs(audio.verses) != null;
        if (playable) {
          _audioByReelId[reel.id] = audio;
        }
      }
      gate.complete(audio);
      return audio;
    } catch (error, stack) {
      if (!gate.isCompleted) {
        // Attach a listener before completeError so tests/zones don't see
        // an unhandled async error when prefetch is the only caller.
        unawaited(gate.future.then<void>((_) {}, onError: (_, __) {}));
        gate.completeError(error, stack);
      }
      rethrow;
    } finally {
      if (identical(_audioMetaInFlight[reel.id], gate.future)) {
        _audioMetaInFlight.remove(reel.id);
      }
    }
  }

  String verseTextFor(Reel reel) {
    return _verseTextByReelId[reel.id] ?? 'Loading verse…';
  }

  String? activeVerseTextFor(Reel reel) {
    final verse = activeVerseNumber;
    if (verse == null) {
      return null;
    }
    return _verseTextByReelVerse[_verseKey(reel.id, verse)];
  }

  String displayVerseTextFor(Reel reel) {
    if (voiceoverPresentation == VoiceoverPresentation.playingActiveVerse &&
        _voiceoverReelId == reel.id) {
      return activeVerseTextFor(reel) ?? verseTextFor(reel);
    }
    return verseTextFor(reel);
  }

  String _verseKey(int reelId, int verse) => '$reelId:$verse';

  Future<void> _ensureVerseText(Reel reel, {bool force = false}) async {
    if (!force) {
      if (_verseTextByReelId.containsKey(reel.id)) {
        return;
      }
      final inFlight = _verseTextInFlight[reel.id];
      if (inFlight != null) {
        await inFlight;
        return;
      }
    }

    // Register before any await so concurrent callers join this load.
    final gate = Completer<void>();
    _verseTextInFlight[reel.id] = gate.future;
    final versionId = translationVersion;
    final translationEpoch = _translationEpoch;
    try {
      if (!force) {
        final cached = await _storage.readCachedVerseText(
          reelId: reel.id,
          versionId: versionId,
        );
        if (translationEpoch != _translationEpoch) {
          return;
        }
        if (cached != null) {
          _verseTextByReelId[reel.id] = cached;
          _notifyIfActive();
          return;
        }
        if (_verseTextByReelId.containsKey(reel.id)) {
          return;
        }
      }

      try {
        final verse = await _api.fetchVerse(reel: reel, versionId: versionId);
        if (translationEpoch != _translationEpoch) {
          return;
        }
        _verseTextByReelId[reel.id] = verse.text;
        if (shouldCacheVerseText(verse.text)) {
          await _storage.cacheVerseText(
            reelId: reel.id,
            versionId: versionId,
            text: verse.text,
          );
        }
        _notifyIfActive();
      } catch (_) {
        if (translationEpoch != _translationEpoch) {
          return;
        }
        _verseTextByReelId[reel.id] = 'Could not load ${reel.reference}';
        _notifyIfActive();
      }
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
      if (identical(_verseTextInFlight[reel.id], gate.future)) {
        _verseTextInFlight.remove(reel.id);
      }
    }
  }

  Future<void> _ensureSingleVerseText(Reel reel, int verse) async {
    final key = _verseKey(reel.id, verse);
    if (_verseTextByReelVerse.containsKey(key)) {
      return;
    }
    if (reel.startVerse == reel.endVerse &&
        _verseTextByReelId.containsKey(reel.id)) {
      _verseTextByReelVerse[key] = _verseTextByReelId[reel.id]!;
      return;
    }
    try {
      final item = await _api.fetchVerse(
        reel: reel,
        versionId: translationVersion,
        startVerse: verse,
        endVerse: verse,
      );
      _verseTextByReelVerse[key] = item.text;
      _notifyIfActive();
    } catch (_) {
      // Leave missing; UI falls back to full section text.
    }
  }

  Future<void> _ensurePerVerseTexts(Reel reel, {bool force = false}) async {
    final futures = <Future<void>>[];
    for (var verse = reel.startVerse; verse <= reel.endVerse; verse++) {
      final key = _verseKey(reel.id, verse);
      if (!force && _verseTextByReelVerse.containsKey(key)) {
        continue;
      }
      futures.add(_ensureSingleVerseText(reel, verse));
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> toggleReelLike(Reel reel) async {
    final index = _reels.indexWhere((item) => item.id == reel.id);
    if (index == -1) {
      return;
    }

    final liked = reel.likedByMe;
    await HapticFeedback.lightImpact();
    final status = liked ? await _api.unlikeReel(reel.id) : await _api.likeReel(reel.id);
    _reels[index] = reel.copyWith(
      likedByMe: status.liked,
      likeCount: status.likeCount,
    );

    if (status.liked) {
      await _storage.rememberLikedReel(reel.id);
    } else {
      await _storage.forgetLikedReel(reel.id);
    }
    notifyListeners();
  }

  Future<List<Comment>> loadComments(int reelId) async {
    final comments = await _api.fetchComments(reelId);
    _commentsByReelId[reelId] = comments;
    notifyListeners();
    return comments;
  }

  Future<Comment> addComment(int reelId, String body, {int? parentId}) async {
    final comment = await _api.postComment(reelId, body, parentId: parentId);
    final comments = List<Comment>.from(_commentsByReelId[reelId] ?? const [])
      ..add(comment);
    _commentsByReelId[reelId] = comments;

    final index = _reels.indexWhere((item) => item.id == reelId);
    if (index != -1) {
      _reels[index] = _reels[index].copyWith(commentCount: _reels[index].commentCount + 1);
    }
    notifyListeners();
    return comment;
  }

  Future<void> toggleCommentLike(Comment comment) async {
    final comments = _commentsByReelId[comment.reelId];
    if (comments == null) {
      return;
    }

    final index = comments.indexWhere((item) => item.id == comment.id);
    if (index == -1) {
      return;
    }

    final status = comment.likedByMe
        ? await _api.unlikeComment(comment.id)
        : await _api.likeComment(comment.id);
    await HapticFeedback.selectionClick();
    comments[index] = comment.copyWith(
      likedByMe: status.liked,
      likeCount: status.likeCount,
    );
    _commentsByReelId[comment.reelId] = List<Comment>.from(comments);
    notifyListeners();
  }

  /// Bind chunk UI to [reel] immediately (before audio URL / play).
  Future<void> _beginActiveVersePresentation(Reel reel) async {
    _voiceoverReelId = reel.id;
    activeVerseNumber = reel.startVerse;
    voiceoverPresentation = VoiceoverPresentation.playingActiveVerse;
    await _ensureSingleVerseText(reel, reel.startVerse);
    _notifyIfActive();
  }

  bool _isVisibilityCurrent(int? visibilityGeneration) {
    return visibilityGeneration == null ||
        visibilityGeneration == _visibleWorkGeneration;
  }

  bool _isPlaybackCurrent(int epoch, int? visibilityGeneration) {
    return epoch == _playbackEpoch && _isVisibilityCurrent(visibilityGeneration);
  }

  Future<Duration?> _setUrlIfCurrent(String url, int epoch) async {
    if (epoch != _playbackEpoch) {
      return null;
    }
    _activeBindUrl = url;
    _activeBindEpoch = epoch;
    final duration = await _audioPlayer.setUrl(url);
    if (epoch != _playbackEpoch) {
      // A superseded setUrl may have overwritten the player; restore current bind.
      final restoreUrl = _activeBindUrl;
      if (_activeBindEpoch == _playbackEpoch && restoreUrl != null) {
        await _audioPlayer.setUrl(restoreUrl);
      }
      return null;
    }
    return duration;
  }

  Future<bool> _abortPlayVoiceoverIfSuperseded(
    Reel reel,
    int epoch,
    int? visibilityGeneration,
  ) async {
    if (_isPlaybackCurrent(epoch, visibilityGeneration)) {
      return false;
    }
    // Another bind owns the player/epoch — do not stop it.
    if (epoch == _playbackEpoch && _voiceoverReelId == reel.id) {
      await stopVoiceover();
    }
    return true;
  }

  Future<void> playVoiceover(
    Reel reel, {
    int? visibilityGeneration,
  }) async {
    final alreadyBegunForReel = _voiceoverReelId == reel.id &&
        voiceoverPresentation == VoiceoverPresentation.playingActiveVerse &&
        _clipVerses.isEmpty &&
        !_audioPlayer.playing;
    if (alreadyBegunForReel) {
      // Keep chunk presentation; only reset clip bookkeeping before audio bind.
      _positionSub?.cancel();
      _positionSub = null;
      _clipFinishing = false;
    } else {
      await stopVoiceover();
      if (!_isVisibilityCurrent(visibilityGeneration)) {
        return;
      }
      // Restore chunk presentation before awaiting audio so the UI never flashes
      // full section text while fetch/setUrl runs.
      await _beginActiveVersePresentation(reel);
    }
    if (!_isVisibilityCurrent(visibilityGeneration)) {
      return;
    }

    // Claim this bind attempt; any later stop/playVoiceover invalidates us.
    final epoch = ++_playbackEpoch;

    final audio = await _ensureAudioMeta(reel);
    if (await _abortPlayVoiceoverIfSuperseded(
      reel,
      epoch,
      visibilityGeneration,
    )) {
      return;
    }
    if (!isPlayableAudioUrl(audio.audioUrl) || audio.verses.isEmpty) {
      voiceoverPresentation = VoiceoverPresentation.sectionIdle;
      activeVerseNumber = null;
      _notifyIfActive();
      throw StateError('Audio unavailable for ${reel.reference}');
    }

    final startMs = sectionStartMs(audio.verses);
    if (startMs == null) {
      voiceoverPresentation = VoiceoverPresentation.sectionIdle;
      activeVerseNumber = null;
      _notifyIfActive();
      throw StateError('Audio unavailable for ${reel.reference}');
    }

    await _ensureVerseText(reel);
    if (await _abortPlayVoiceoverIfSuperseded(
      reel,
      epoch,
      visibilityGeneration,
    )) {
      return;
    }
    await _ensurePerVerseTexts(reel);
    if (await _abortPlayVoiceoverIfSuperseded(
      reel,
      epoch,
      visibilityGeneration,
    )) {
      return;
    }

    final duration = await _setUrlIfCurrent(audio.audioUrl, epoch);
    if (duration == null ||
        await _abortPlayVoiceoverIfSuperseded(
          reel,
          epoch,
          visibilityGeneration,
        )) {
      return;
    }
    _clipVerses = clampOpenEndedVerseTimings(
      List<BibleAudioVerseTiming>.from(audio.verses),
      duration.inMilliseconds,
    );
    await _audioPlayer.seek(Duration(milliseconds: startMs));
    if (await _abortPlayVoiceoverIfSuperseded(
      reel,
      epoch,
      visibilityGeneration,
    )) {
      return;
    }
    _voiceoverReelId = reel.id;
    activeVerseNumber = _clipVerses.first.verse;
    voiceoverPresentation = VoiceoverPresentation.playingActiveVerse;
    _clipFinishing = false;
    await _applyAudioVolume();
    await _applyAudioSpeed();
    _listenToPosition();
    // Notify before play so verse UI updates even when browsers block autoplay.
    _notifyIfActive();
    if (await _abortPlayVoiceoverIfSuperseded(
      reel,
      epoch,
      visibilityGeneration,
    )) {
      return;
    }
    try {
      await _audioPlayer.play();
    } catch (_) {
      _notifyIfActive();
      rethrow;
    }
  }

  void _listenToPosition() {
    _positionSub?.cancel();
    _positionSub = _audioPlayer.positionStream.listen((position) {
      if (_voiceoverReelId == null || _clipVerses.isEmpty || _clipFinishing) {
        return;
      }
      final ms = position.inMilliseconds;
      if (isVerseClipFinished(_clipVerses, ms)) {
        _clipFinishing = true;
        unawaited(_finishVerseClip());
        return;
      }
      final nextActive = activeVerseAtPositionMs(_clipVerses, ms);
      if (nextActive != null && nextActive != activeVerseNumber) {
        activeVerseNumber = nextActive;
        final playing = _reelById(_voiceoverReelId);
        if (playing != null) {
          unawaited(_ensureSingleVerseText(playing, nextActive));
        }
        _notifyIfActive();
      }
    });
  }

  Reel? _reelById(int? id) {
    if (id == null) {
      return null;
    }
    for (final reel in _reels) {
      if (reel.id == id) {
        return reel;
      }
    }
    return null;
  }

  Future<void> _finishVerseClip() async {
    _positionSub?.cancel();
    _positionSub = null;
    if (_audioPlayerOverride != null || _lazyAudioPlayer != null) {
      await _audioPlayer.pause();
    }
    voiceoverPresentation = VoiceoverPresentation.sectionReveal;
    activeVerseNumber = null;
    _notifyIfActive();
  }

  Future<void> stopVoiceover() async {
    _playbackEpoch++;
    _activeBindUrl = null;
    _activeBindEpoch = 0;
    _positionSub?.cancel();
    _positionSub = null;
    _clipFinishing = false;
    _clipVerses = const [];
    activeVerseNumber = null;
    if (voiceoverPresentation == VoiceoverPresentation.playingActiveVerse ||
        voiceoverPresentation == VoiceoverPresentation.sectionReveal) {
      voiceoverPresentation = VoiceoverPresentation.sectionIdle;
    }
    if (_audioPlayerOverride == null && _lazyAudioPlayer == null) {
      _voiceoverReelId = null;
      return;
    }
    await _audioPlayer.stop();
    _voiceoverReelId = null;
  }

  /// Peek intended tap action without mutating playback (for optimistic UI).
  VoiceoverTapAction peekVoiceoverTapAction(Reel reel) {
    if (showClickToStart) {
      return VoiceoverTapAction.start;
    }
    final clipDone = voiceoverPresentation == VoiceoverPresentation.sectionReveal &&
        _voiceoverReelId == reel.id;
    return resolveVoiceoverTapAction(
      isCurrentReelLoaded: _voiceoverReelId == reel.id,
      playing: _audioPlayer.playing,
      completed: clipDone ||
          _audioPlayer.processingState == ProcessingState.completed,
    );
  }

  /// Tap-to-toggle: pause / resume / replay finished audio / start if needed.
  Future<VoiceoverTapAction> toggleVoiceoverPlayback(Reel reel) async {
    if (showClickToStart) {
      await startFromClickToStart();
      return VoiceoverTapAction.start;
    }

    final action = peekVoiceoverTapAction(reel);

    switch (action) {
      case VoiceoverTapAction.pause:
        await _audioPlayer.pause();
      case VoiceoverTapAction.resume:
        if (voiceoverPresentation != VoiceoverPresentation.playingActiveVerse) {
          voiceoverPresentation = VoiceoverPresentation.playingActiveVerse;
          notifyListeners();
        }
        await _audioPlayer.play();
      case VoiceoverTapAction.replay:
        await playVoiceover(reel);
      case VoiceoverTapAction.start:
        await playVoiceover(reel);
    }
    return action;
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _audioPlayerOverride?.dispose();
    _lazyAudioPlayer?.dispose();
    super.dispose();
  }
}
