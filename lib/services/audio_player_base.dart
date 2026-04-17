import 'dart:async';

/// 音频播放器抽象基类
abstract class AudioPlayerServiceBase {
  final _playbackStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _currentIndexController = StreamController<int>.broadcast();
  final _completeController = StreamController<void>.broadcast();

  Stream<PlayerState> get playbackStateStream => _playbackStateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<int> get currentIndexStream => _currentIndexController.stream;
  Stream<void> get completeStream => _completeController.stream;

  bool get isInitialized;
  bool get isPlaying;
  Duration get currentPosition;
  Duration get duration;
  int get currentIndex;

  Future<void> playFile(String filePath, {bool isVideo = false});
  Future<void> playUrl(String url, {bool isVideo = false});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> seekForward(Duration duration);
  Future<void> seekBackward(Duration duration);
  Future<void> playNext();
  Future<void> playPrevious();
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> dispose();

  void closeStreams() {
    _playbackStateController.close();
    _positionController.close();
    _durationController.close();
    _currentIndexController.close();
    _completeController.close();
  }
}

/// 播放器状态枚举
enum PlayerState { idle, loading, playing, paused, completed }
