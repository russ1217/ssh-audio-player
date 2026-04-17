import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_player_base.dart';

/// Linux 平台音频播放器空实现
class AudioPlayerService extends AudioPlayerServiceBase {
  bool _isInitialized = false;

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
  Future<void> playUrl(String url, {bool isVideo = false}) async {
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
    // Linux stub 不需要关闭任何资源
  }
}
