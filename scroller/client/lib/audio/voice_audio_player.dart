import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Thin playback surface so tests can inject a fake without platform audio.
abstract class VoiceAudioPlayer {
  Stream<Duration> get positionStream;
  bool get playing;
  ProcessingState get processingState;

  Future<Duration?> setUrl(String url);
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class JustAudioVoicePlayer implements VoiceAudioPlayer {
  JustAudioVoicePlayer([AudioPlayer? player]) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  bool get playing => _player.playing;

  @override
  ProcessingState get processingState => _player.processingState;

  @override
  Future<Duration?> setUrl(String url) => _player.setUrl(url);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() => _player.dispose();
}
