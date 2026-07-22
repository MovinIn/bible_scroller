import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _deviceIdKey = 'device_id';
  static const _translationKey = 'translation_version';
  static const _autoplayVoiceKey = 'autoplay_voice';
  static const _voiceMutedKey = 'voice_muted';
  static const _voicePlaybackSpeedKey = 'voice_playback_speed';
  static const _discoveryModeKey = 'discovery_mode';
  static const minVoicePlaybackSpeed = 0.5;
  static const maxVoicePlaybackSpeed = 2.0;
  static const defaultVoicePlaybackSpeed = 1.0;
  static const _likedReelsBox = 'liked_reels';
  static const _verseCacheBox = 'verse_cache';

  SharedPreferences? _prefs;
  Box<int>? _likedReelsBoxInstance;
  Box<String>? _verseCacheBoxInstance;

  Future<void> init({String? hivePath}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    _prefs = await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> _requirePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<Box<int>> _requireLikedReelsBox() async {
    if (_likedReelsBoxInstance != null && _likedReelsBoxInstance!.isOpen) {
      return _likedReelsBoxInstance!;
    }
    _likedReelsBoxInstance = await Hive.openBox<int>(_likedReelsBox);
    return _likedReelsBoxInstance!;
  }

  Future<Box<String>> _requireVerseCacheBox() async {
    if (_verseCacheBoxInstance != null && _verseCacheBoxInstance!.isOpen) {
      return _verseCacheBoxInstance!;
    }
    _verseCacheBoxInstance = await Hive.openBox<String>(_verseCacheBox);
    return _verseCacheBoxInstance!;
  }

  Future<String?> readDeviceId() async {
    final prefs = await _requirePrefs();
    return prefs.getString(_deviceIdKey);
  }

  Future<void> saveDeviceId(String deviceId) async {
    final prefs = await _requirePrefs();
    await prefs.setString(_deviceIdKey, deviceId);
  }

  Future<String> readTranslationVersion({String fallback = 'esv'}) async {
    final prefs = await _requirePrefs();
    final stored = prefs.getString(_translationKey);
    if (stored == null || stored.isEmpty) {
      return fallback;
    }
    // Free Bible Brain keys typically lack NIV text rights; prefer ESV.
    if (stored == 'niv') {
      return fallback;
    }
    return stored;
  }

  Future<void> saveTranslationVersion(String versionId) async {
    final prefs = await _requirePrefs();
    await prefs.setString(_translationKey, versionId);
  }

  Future<bool> readAutoplayVoice({bool fallback = true}) async {
    final prefs = await _requirePrefs();
    return prefs.getBool(_autoplayVoiceKey) ?? fallback;
  }

  Future<void> saveAutoplayVoice(bool enabled) async {
    final prefs = await _requirePrefs();
    await prefs.setBool(_autoplayVoiceKey, enabled);
  }

  Future<bool> readVoiceMuted({bool fallback = false}) async {
    final prefs = await _requirePrefs();
    return prefs.getBool(_voiceMutedKey) ?? fallback;
  }

  Future<void> saveVoiceMuted(bool muted) async {
    final prefs = await _requirePrefs();
    await prefs.setBool(_voiceMutedKey, muted);
  }

  Future<double> readVoicePlaybackSpeed({
    double fallback = defaultVoicePlaybackSpeed,
  }) async {
    final prefs = await _requirePrefs();
    final stored = prefs.getDouble(_voicePlaybackSpeedKey);
    if (stored == null) {
      return fallback;
    }
    return clampVoicePlaybackSpeed(stored);
  }

  Future<void> saveVoicePlaybackSpeed(double speed) async {
    final prefs = await _requirePrefs();
    await prefs.setDouble(
      _voicePlaybackSpeedKey,
      clampVoicePlaybackSpeed(speed),
    );
  }

  static double clampVoicePlaybackSpeed(double speed) {
    if (speed < minVoicePlaybackSpeed) {
      return minVoicePlaybackSpeed;
    }
    if (speed > maxVoicePlaybackSpeed) {
      return maxVoicePlaybackSpeed;
    }
    return speed;
  }

  Future<bool> readDiscoveryMode({bool fallback = false}) async {
    final prefs = await _requirePrefs();
    return prefs.getBool(_discoveryModeKey) ?? fallback;
  }

  Future<void> saveDiscoveryMode(bool enabled) async {
    final prefs = await _requirePrefs();
    await prefs.setBool(_discoveryModeKey, enabled);
  }

  Future<void> rememberLikedReel(int reelId) async {
    final box = await _requireLikedReelsBox();
    await box.put(reelId, 1);
  }

  Future<void> forgetLikedReel(int reelId) async {
    final box = await _requireLikedReelsBox();
    await box.delete(reelId);
  }

  Future<bool> isReelCachedAsLiked(int reelId) async {
    final box = await _requireLikedReelsBox();
    return box.containsKey(reelId);
  }

  bool isReelCachedAsLikedSync(int reelId) {
    final box = _likedReelsBoxInstance;
    if (box == null || !box.isOpen) {
      return false;
    }
    return box.containsKey(reelId);
  }

  String _verseCacheKey({required int reelId, required String versionId}) {
    return '$reelId:$versionId';
  }

  Future<void> cacheVerseText({
    required int reelId,
    required String versionId,
    required String text,
  }) async {
    final box = await _requireVerseCacheBox();
    await box.put(
      _verseCacheKey(reelId: reelId, versionId: versionId),
      text,
    );
  }

  Future<String?> readCachedVerseText({
    required int reelId,
    required String versionId,
  }) async {
    final box = await _requireVerseCacheBox();
    return box.get(
      _verseCacheKey(reelId: reelId, versionId: versionId),
    );
  }
}
