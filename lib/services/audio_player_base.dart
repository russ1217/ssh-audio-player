import 'dart:async';

/// 音频播放器抽象基类
abstract class AudioPlayerServiceBase {
  // Stream controllers - protected style (no underscore prefix for subclass access)
  late final StreamController<PlayerState> playbackStateController;
  late final StreamController<Duration> positionController;
  late final StreamController<Duration> durationController;
  late final StreamController<int> currentIndexController;
  late final StreamController<void> completeController;

  Stream<PlayerState> get playbackStateStream => playbackStateController.stream;
  Stream<Duration> get positionStream => positionController.stream;
  Stream<Duration> get durationStream => durationController.stream;
  Stream<int> get currentIndexStream => currentIndexController.stream;
  Stream<void> get completeStream => completeController.stream;

  bool get isInitialized;
  bool get isPlaying;
  Duration get currentPosition;
  Duration get duration;
  int get currentIndex;

  /// 确保播放器已初始化（解决异步初始化竞态条件）
  Future<void> ensureInitialized();

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
    playbackStateController.close();
    positionController.close();
    durationController.close();
    currentIndexController.close();
    completeController.close();
  }
}

/// 播放器状态枚举
enum PlayerState { idle, loading, playing, paused, completed }
