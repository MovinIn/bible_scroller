import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/position_cookie.dart';
import '../services/storage_service.dart';
import '../utils/startup_timing.dart';
import '../utils/verse_cache_policy.dart';
import '../utils/voiceover_tap_action.dart';

class ReelsController extends ChangeNotifier {
  ReelsController({
    required ApiClient api,
    required StorageService storage,
    AudioPlayer? audioPlayer,
  })  : _api = api,
        _storage = storage,
        _audioPlayerOverride = audioPlayer;

  final ApiClient _api;
  final StorageService _storage;
  final AudioPlayer? _audioPlayerOverride;
  AudioPlayer? _lazyAudioPlayer;

  final List<Reel> _reels = [];
  final Map<int, String> _verseTextByReelId = {};
  final Map<int, List<Comment>> _commentsByReelId = {};

  bool loading = true;
  bool loadingMore = false;
  bool loadingPrevious = false;
  String? error;
  String translationVersion = 'niv';
  bool autoplayVoice = true;
  bool isMuted = false;
  List<BibleVersion> versions = const [];
  List<String> books = const [];
  int? _nextCursor;
  int? _prevCursor;
  int _currentIndex = 0;
  int? _voiceoverReelId;
  Future<void>? _booksLoadFuture;
  Future<void>? _versionsLoadFuture;
  Future<void>? _visibleReelWork;
  int _visibleWorkGeneration = 0;

  List<Reel> get reels => List.unmodifiable(_reels);
  int get currentIndex => _currentIndex;
  Reel? get currentReel => _reels.isEmpty ? null : _reels[_currentIndex];
  bool get canLoadNext => _nextCursor != null;
  bool get canLoadPrevious => _prevCursor != null;

  AudioPlayer get _audioPlayer {
    if (_audioPlayerOverride != null) {
      return _audioPlayerOverride!;
    }
    return _lazyAudioPlayer ??= AudioPlayer();
  }

  Future<void> initialize() async {
    await StartupTiming.track('init.prefs', () async {
      translationVersion = await _storage.readTranslationVersion();
      autoplayVoice = await _storage.readAutoplayVoice();
      isMuted = await _storage.readVoiceMuted();
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
        BibleVersion(versionId: 'niv', name: 'New International Version'),
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
    final ReelFeed feed;
    try {
      feed = await _api.fetchReels(limit: 10, book: book);
    } catch (_) {
      return null;
    }
    if (feed.items.isEmpty) {
      return null;
    }
    _reels
      ..clear()
      ..addAll(feed.items);
    _nextCursor = feed.nextCursor;
    _prevCursor = feed.prevCursor;
    _currentIndex = 0;
    notifyListeners();
    unawaited(_scheduleOnReelVisible(0));
    return 0;
  }

  Future<void> refreshFeed() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final resumeId = readLastReelIdFromCookie();
      var feed = await StartupTiming.track(
        'feed.fetchReels',
        () => _api.fetchReels(limit: 10, fromId: resumeId),
      );
      if (feed.items.isEmpty && resumeId != null) {
        clearLastReelCookie();
        feed = await _api.fetchReels(limit: 10);
      }
      _reels
        ..clear()
        ..addAll(feed.items);
      _nextCursor = feed.nextCursor;
      _prevCursor = feed.prevCursor;
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

  Future<void> _scheduleOnReelVisible(int index) {
    final previous = _visibleReelWork;
    final generation = ++_visibleWorkGeneration;
    final work = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // Prior visibility work may have failed; still run the latest.
        }
      }
      if (generation != _visibleWorkGeneration) {
        return;
      }
      await _runOnReelVisible(index, generation);
    }();
    _visibleReelWork = work;
    return work;
  }

  Future<void> _runOnReelVisible(int index, int generation) async {
    if (generation != _visibleWorkGeneration) {
      return;
    }
    await StartupTiming.track('reel.loadMoreIfNeeded', () => loadMoreIfNeeded(index));
    if (generation != _visibleWorkGeneration) {
      return;
    }
    if (index < _reels.length) {
      writeLastReelCookie(_reels[index].id);
    }
    if (!autoplayVoice || index >= _reels.length) {
      return;
    }
    final reel = _reels[index];
    if (!_verseTextByReelId.containsKey(reel.id)) {
      await StartupTiming.track('reel.ensureVerseText', () => _ensureVerseText(reel));
    }
    if (generation != _visibleWorkGeneration) {
      return;
    }
    try {
      await StartupTiming.track('reel.playVoiceover', () => playVoiceover(reel));
    } catch (_) {
      // Audio may be unavailable without Bible Brain API key.
    }
  }

  Future<void> onReelVisible(int index) => _scheduleOnReelVisible(index);

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

  Future<void> _applyAudioVolume() async {
    try {
      await _audioPlayer.setVolume(isMuted ? 0.0 : 1.0);
    } catch (_) {
      // Audio player may be unavailable in tests or before first playback.
    }
  }

  Future<void> loadMoreIfNeeded(int index) async {
    _currentIndex = index;
    if (index >= _reels.length - 2 && _nextCursor != null && !loadingMore) {
      loadingMore = true;
      notifyListeners();
      try {
        final feed = await _api.fetchReels(cursor: _nextCursor, limit: 10);
        _reels.addAll(feed.items);
        _nextCursor = feed.nextCursor;
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
  }

  /// Loads the next page when the user is on the last loaded reel.
  Future<bool> ensureNextPageLoaded() async {
    if (_nextCursor == null || loadingMore) {
      return false;
    }

    loadingMore = true;
    notifyListeners();
    try {
      final feed = await _api.fetchReels(cursor: _nextCursor, limit: 10);
      if (feed.items.isEmpty) {
        _nextCursor = null;
        return false;
      }
      _reels.addAll(feed.items);
      _nextCursor = feed.nextCursor;
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
    if (_prevCursor == null || loadingPrevious) {
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
    await _storage.saveTranslationVersion(versionId);
    _verseTextByReelId.clear();
    notifyListeners();
    if (currentReel != null) {
      await _ensureVerseText(currentReel!, force: true);
    }
  }

  String verseTextFor(Reel reel) {
    return _verseTextByReelId[reel.id] ?? 'Loading verse…';
  }

  Future<void> _ensureVerseText(Reel reel, {bool force = false}) async {
    if (!force) {
      final cached = await _storage.readCachedVerseText(
        reelId: reel.id,
        versionId: translationVersion,
      );
      if (cached != null) {
        _verseTextByReelId[reel.id] = cached;
        notifyListeners();
        return;
      }
      if (_verseTextByReelId.containsKey(reel.id)) {
        return;
      }
    }

    try {
      final verse = await _api.fetchVerse(reel: reel, versionId: translationVersion);
      _verseTextByReelId[reel.id] = verse.text;
      if (shouldCacheVerseText(verse.text)) {
        await _storage.cacheVerseText(
          reelId: reel.id,
          versionId: translationVersion,
          text: verse.text,
        );
      }
      notifyListeners();
    } catch (_) {
      _verseTextByReelId[reel.id] = 'Could not load ${reel.reference}';
      notifyListeners();
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

  Future<void> playVoiceover(Reel reel) async {
    await stopVoiceover();
    final audio = await _api.fetchAudio(reel: reel, versionId: translationVersion);
    if (!isPlayableAudioUrl(audio.audioUrl)) {
      throw StateError('Audio unavailable for ${reel.reference}');
    }
    await _audioPlayer.setUrl(audio.audioUrl);
    _voiceoverReelId = reel.id;
    await _applyAudioVolume();
    await _audioPlayer.play();
  }

  Future<void> stopVoiceover() async {
    if (_audioPlayerOverride == null && _lazyAudioPlayer == null) {
      _voiceoverReelId = null;
      return;
    }
    await _audioPlayer.stop();
    _voiceoverReelId = null;
  }

  /// Tap-to-toggle: pause / resume / replay finished audio / start if needed.
  Future<VoiceoverTapAction> toggleVoiceoverPlayback(Reel reel) async {
    final action = resolveVoiceoverTapAction(
      isCurrentReelLoaded: _voiceoverReelId == reel.id,
      playing: _audioPlayer.playing,
      completed: _audioPlayer.processingState == ProcessingState.completed,
    );

    switch (action) {
      case VoiceoverTapAction.pause:
        await _audioPlayer.pause();
      case VoiceoverTapAction.resume:
        await _audioPlayer.play();
      case VoiceoverTapAction.replay:
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
      case VoiceoverTapAction.start:
        await playVoiceover(reel);
    }
    return action;
  }

  @override
  void dispose() {
    _audioPlayerOverride?.dispose();
    _lazyAudioPlayer?.dispose();
    super.dispose();
  }
}
