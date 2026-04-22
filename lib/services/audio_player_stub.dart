import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_player_base.dart';

/// Linux 平台音频播放器空实现
class AudioPlayerService extends AudioPlayerServiceBase {
  bool _isInitialized = false;

  // ✅ 关键修复：实现所有必需的Stream getters
  final StreamController<PlayerState> _playbackStateController = StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  final StreamController<int> _currentIndexController = StreamController<int>.broadcast();
  final StreamController<void> _completeController = StreamController<void>.broadcast();

  @override
  Stream<PlayerState> get playbackStateStream => _playbackStateController.stream;
  
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  
  @override
  Stream<int> get currentIndexStream => _currentIndexController.stream;
  
  @override
  Stream<void> get completeStream => _completeController.stream;

  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isPlaying => false;
  
  @override
  Duration get currentPosition => Duration.zero;
  
  @override
  Duration get duration => Duration.zero;
  
  @override
  int get currentIndex => 0;

  AudioPlayerService() {
    _initialize();
  }

  @override
  Future<void> ensureInitialized() async {
    // Linux平台不需要初始化，直接返回
    _isInitialized = true;
  }

  Future<void> _initialize() async {
    debugPrint('⚠️ Linux 平台不支持音频播放');
    _isInitialized = false;
  }

  @override
  Future<void> playFile(String filePath, {bool isVideo = false}) async {
    debugPrint('⚠️ Linux 平台不支持播放文件: $filePath');
  }

  @override
  Future<void> playUrl(String url, {bool isVideo = false, Duration? initialPosition}) async {
    debugPrint('⚠️ Linux 平台不支持播放 URL: $url');
  }

  @override
  Future<void> play() async {
    debugPrint('⚠️ Linux 平台不支持播放');
  }

  @override
  Future<void> pause() async {
    debugPrint('⚠️ Linux 平台不支持暂停');
  }

  @override
  Future<void> stop() async {
    debugPrint('⚠️ Linux 平台不支持停止');
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('⚠️ Linux 平台不支持 seek');
  }

  @override
  Future<void> seekForward(Duration duration) async {
    debugPrint('⚠️ Linux 平台不支持快进');
  }

  @override
  Future<void> seekBackward(Duration duration) async {
    debugPrint('⚠️ Linux 平台不支持快退');
  }

  @override
  Future<void> playNext() async {
    debugPrint('⚠️ Linux 平台不支持下一曲');
  }

  @override
  Future<void> playPrevious() async {
    debugPrint('⚠️ Linux 平台不支持上一曲');
  }

  @override
  Future<void> setVolume(double volume) async {
    debugPrint('⚠️ Linux 平台不支持设置音量');
  }

  @override
  Future<void> setSpeed(double speed) async {
    debugPrint('⚠️ Linux 平台不支持设置播放速度');
  }

  @override
  Future<void> dispose() async {
    // ✅ 关闭所有Stream controllers
    await _playbackStateController.close();
    await _positionController.close();
    await _durationController.close();
    await _currentIndexController.close();
    await _completeController.close();
  }
}
