import 'dart:async';

/// 音频播放器抽象基类
abstract class AudioPlayerServiceBase {
  // Stream controllers - abstract getters, implemented by subclasses
  Stream<PlayerState> get playbackStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<int> get currentIndexStream;
  Stream<void> get completeStream;

  bool get isInitialized;
  bool get isPlaying;
  Duration get currentPosition;
  Duration get duration;
  int get currentIndex;

  /// 确保播放器已初始化（解决异步初始化竞态条件）
  Future<void> ensureInitialized();

  Future<void> playFile(String filePath, {bool isVideo = false});
  Future<void> playUrl(String url, {bool isVideo = false, Duration? initialPosition});
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
}

/// 播放器状态枚举
enum PlayerState { idle, loading, playing, paused, completed }
